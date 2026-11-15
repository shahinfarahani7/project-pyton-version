"""Prepaid FIBON book for the dev customer portal.

Balances are integer atomic units. Each wallet is a real sub-account.
A task hold is drawn across wallets in order, then spent or released once.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from typing import Any
from uuid import UUID

PRIMARY_WALLET_ID = "wal_primary"
MAX_WALLET_NAME_LENGTH = 80
MAX_WALLET_TOKENS = 1_000_000
DEV_GRANT_TOKENS = 1_000_000
_RELEASE_STATUSES = frozenset({"failed", "cancelled", "expired"})


def _whole(name: str, value: object) -> int:
    if type(value) is not int:
        raise ValueError(f"{name}_MUST_BE_INT")
    return value


@dataclass
class WalletAccount:
    wallet_id: str
    name: str
    builtin: bool
    available: int = 0
    reserved: int = 0
    spent: int = 0
    funded: int = 0


@dataclass(frozen=True, slots=True)
class HoldSlice:
    wallet_id: str
    amount: int


@dataclass(frozen=True, slots=True)
class JournalLeg:
    account: str
    amount: int


@dataclass(frozen=True, slots=True)
class JournalEntry:
    kind: str
    task_id: str | None
    legs: tuple[JournalLeg, ...]


@dataclass(frozen=True, slots=True)
class SettlementReceipt:
    task_id: str
    status: str
    charge_atomic: int
    worker_reward_atomic: int
    treasury_atomic: int
    slices: tuple[HoldSlice, ...]


@dataclass
class TaskPosting:
    task_id: str
    difficulty_grade: int
    charge_atomic: int
    worker_reward_atomic: int
    treasury_atomic: int
    status: str
    slices: tuple[HoldSlice, ...]
    invoice: dict[str, Any]
    spent_at: str | None = None
    receipt: SettlementReceipt | None = None


@dataclass
class WorkspaceBook:
    workspace_id: UUID
    wallets: list[WalletAccount] = field(default_factory=list)
    postings: dict[str, TaskPosting] = field(default_factory=dict)
    journal: list[JournalEntry] = field(default_factory=list)

    @classmethod
    def open(cls, workspace_id: UUID, *, grant_atomic: int = 0) -> WorkspaceBook:
        grant = _whole("grant", grant_atomic)
        if grant < 0:
            raise ValueError("NEGATIVE_INPUT")
        book = cls(workspace_id=workspace_id)
        primary = WalletAccount(PRIMARY_WALLET_ID, "Primary", True)
        book.wallets.append(primary)
        if grant:
            book._fund(primary, grant, source="dev-grant", task_id=None)
        book.check_invariants()
        return book

    def available_total(self) -> int:
        return sum(wallet.available for wallet in self.wallets)

    def reserved_total(self) -> int:
        return sum(wallet.reserved for wallet in self.wallets)

    def spent_in_period(self, period: str) -> int:
        total = 0
        for posting in self.postings.values():
            spent_at = posting.spent_at
            if posting.status == "spent" and spent_at is not None and spent_at.startswith(period):
                total += posting.charge_atomic
        return total

    def wallet_rows(self) -> list[dict[str, Any]]:
        return [self._wallet_row(wallet) for wallet in self.wallets]

    def invoice_items(self) -> list[dict[str, Any]]:
        items = [dict(posting.invoice) for posting in self.postings.values()]
        items.sort(key=lambda item: str(item.get("createdAt") or ""), reverse=True)
        return items

    def posting_for(self, task_id: str) -> TaskPosting | None:
        return self.postings.get(task_id)

    def journal_entries(self) -> tuple[JournalEntry, ...]:
        return tuple(self.journal)

    def add_named_wallet(self, *, name: str, amount_atomic: int, unit: int, now: str) -> dict[str, Any]:
        cleaned = name.strip()
        if not cleaned or len(cleaned) > MAX_WALLET_NAME_LENGTH:
            raise ValueError("WALLET_NAME_INVALID")
        amount = _whole("amount", amount_atomic)
        token_unit = _whole("unit", unit)
        if (
            amount <= 0
            or token_unit <= 0
            or amount % token_unit != 0
            or amount // token_unit > MAX_WALLET_TOKENS
        ):
            raise ValueError("WALLET_AMOUNT_INVALID")
        wallet = WalletAccount(
            wallet_id=f"wal_{secrets.token_hex(6)}",
            name=cleaned,
            builtin=False,
        )
        self.wallets.append(wallet)
        self._fund(wallet, amount, source="wallet-fund", task_id=None)
        self.check_invariants()
        return self._wallet_row(wallet)

    def reserve(
        self,
        task_id: str,
        *,
        difficulty_grade: int,
        charge_atomic: int,
        worker_reward_atomic: int,
        treasury_atomic: int,
        now: str,
    ) -> TaskPosting:
        task = _task_id(task_id)
        grade = _whole("grade", difficulty_grade)
        charge = _whole("charge", charge_atomic)
        worker_reward = _whole("workerReward", worker_reward_atomic)
        treasury = _whole("treasury", treasury_atomic)
        if grade < 1 or charge < 0 or worker_reward < 0 or treasury < 0:
            raise ValueError("NEGATIVE_INPUT")
        if worker_reward + treasury != charge:
            raise ValueError("BILLING_SPLIT_MISMATCH")
        if task in self.postings:
            raise ValueError("BILLING_TASK_EXISTS")
        if self.available_total() < charge:
            raise ValueError("INSUFFICIENT_FIBONAI")
        slices = self._plan_draw(charge)
        for wallet, amount in slices:
            self._move(
                wallet,
                amount=amount,
                available_delta=-amount,
                reserved_delta=amount,
                kind="reserve",
                debit=f"wallet:{wallet.wallet_id}:available",
                credit=f"wallet:{wallet.wallet_id}:reserved",
                task_id=task,
            )
        posting = TaskPosting(
            task_id=task,
            difficulty_grade=grade,
            charge_atomic=charge,
            worker_reward_atomic=worker_reward,
            treasury_atomic=treasury,
            status="reserved",
            slices=tuple(HoldSlice(wallet.wallet_id, amount) for wallet, amount in slices),
            invoice=_open_invoice(task, charge, now),
        )
        self.postings[task] = posting
        self.check_invariants()
        return posting

    def settle(self, task_id: str, status: str, *, now: str) -> SettlementReceipt | None:
        posting = self.postings.get(_task_id(task_id))
        if posting is None:
            return None
        if posting.status != "reserved":
            return posting.receipt
        if status == "succeeded":
            self._recognize(posting, now)
            return posting.receipt
        if status not in _RELEASE_STATUSES:
            return None
        self._release(posting, now)
        return posting.receipt

    def check_invariants(self) -> None:
        seen: set[str] = set()
        if not self.wallets or self.wallets[0].wallet_id != PRIMARY_WALLET_ID or not self.wallets[0].builtin:
            raise ValueError("BILLING_INVARIANT")
        for wallet in self.wallets:
            if wallet.wallet_id in seen:
                raise ValueError("BILLING_INVARIANT")
            seen.add(wallet.wallet_id)
            numbers = (wallet.available, wallet.reserved, wallet.spent, wallet.funded)
            if any(type(number) is not int or number < 0 for number in numbers):
                raise ValueError("BILLING_INVARIANT")
            if wallet.available + wallet.reserved + wallet.spent != wallet.funded:
                raise ValueError("BILLING_INVARIANT")
        reserved_holds = 0
        spent_holds = 0
        for posting in self.postings.values():
            sliced = sum(item.amount for item in posting.slices)
            if sliced != posting.charge_atomic:
                raise ValueError("BILLING_INVARIANT")
            if posting.worker_reward_atomic + posting.treasury_atomic != posting.charge_atomic:
                raise ValueError("BILLING_INVARIANT")
            if posting.status == "reserved":
                reserved_holds += posting.charge_atomic
                if posting.invoice.get("status") != "open":
                    raise ValueError("BILLING_INVARIANT")
            elif posting.status == "spent":
                spent_holds += posting.charge_atomic
                if posting.invoice.get("status") != "paid":
                    raise ValueError("BILLING_INVARIANT")
            elif posting.status == "released":
                if posting.invoice.get("status") != "void":
                    raise ValueError("BILLING_INVARIANT")
            else:
                raise ValueError("BILLING_INVARIANT")
            if posting.invoice.get("amountFibonAtomic") != posting.charge_atomic:
                raise ValueError("BILLING_INVARIANT")
        if sum(wallet.reserved for wallet in self.wallets) != reserved_holds:
            raise ValueError("BILLING_INVARIANT")
        if sum(wallet.spent for wallet in self.wallets) != spent_holds:
            raise ValueError("BILLING_INVARIANT")
        for entry in self.journal:
            if len(entry.legs) != 2 or sum(leg.amount for leg in entry.legs) != 0:
                raise ValueError("BILLING_INVARIANT")
            if any(type(leg.amount) is not int or leg.amount == 0 for leg in entry.legs):
                raise ValueError("BILLING_INVARIANT")

    def _plan_draw(self, charge: int) -> list[tuple[WalletAccount, int]]:
        if charge == 0:
            return []
        planned: list[tuple[WalletAccount, int]] = []
        remaining = charge
        for wallet in self.wallets:
            if remaining == 0:
                break
            if wallet.available <= 0:
                continue
            take = wallet.available if wallet.available < remaining else remaining
            planned.append((wallet, take))
            remaining -= take
        if remaining != 0:
            raise ValueError("BILLING_INVARIANT")
        return planned

    def _recognize(self, posting: TaskPosting, now: str) -> None:
        resolved = self._reserved_slices(posting)
        for wallet, amount in resolved:
            self._move(
                wallet,
                amount=amount,
                reserved_delta=-amount,
                spent_delta=amount,
                kind="spend",
                debit=f"wallet:{wallet.wallet_id}:reserved",
                credit="usage:recognized",
                task_id=posting.task_id,
            )
        posting.status = "spent"
        posting.spent_at = now
        posting.invoice["status"] = "paid"
        posting.invoice["updatedAt"] = now
        posting.receipt = _receipt(posting, "spent")
        self.check_invariants()

    def _release(self, posting: TaskPosting, now: str) -> None:
        resolved = self._reserved_slices(posting)
        for wallet, amount in resolved:
            self._move(
                wallet,
                amount=amount,
                reserved_delta=-amount,
                available_delta=amount,
                kind="release",
                debit=f"wallet:{wallet.wallet_id}:reserved",
                credit=f"wallet:{wallet.wallet_id}:available",
                task_id=posting.task_id,
            )
        posting.status = "released"
        posting.invoice["status"] = "void"
        posting.invoice["updatedAt"] = now
        posting.receipt = _receipt(posting, "released")
        self.check_invariants()

    def _reserved_slices(self, posting: TaskPosting) -> list[tuple[WalletAccount, int]]:
        resolved: list[tuple[WalletAccount, int]] = []
        for item in posting.slices:
            wallet = self._wallet(item.wallet_id)
            if item.amount <= 0 or wallet.reserved < item.amount:
                raise ValueError("BILLING_INVARIANT")
            resolved.append((wallet, item.amount))
        return resolved

    def _fund(self, wallet: WalletAccount, amount: int, *, source: str, task_id: str | None) -> None:
        self._move(
            wallet,
            amount=amount,
            available_delta=amount,
            funded_delta=amount,
            kind="fund",
            debit=f"funding:{source}",
            credit=f"wallet:{wallet.wallet_id}:available",
            task_id=task_id,
        )

    def _move(
        self,
        wallet: WalletAccount,
        *,
        amount: int,
        kind: str,
        debit: str,
        credit: str,
        task_id: str | None,
        available_delta: int = 0,
        reserved_delta: int = 0,
        spent_delta: int = 0,
        funded_delta: int = 0,
    ) -> None:
        wallet.available += available_delta
        wallet.reserved += reserved_delta
        wallet.spent += spent_delta
        wallet.funded += funded_delta
        self._post(kind, debit=debit, credit=credit, amount=amount, task_id=task_id)

    def _post(self, kind: str, *, debit: str, credit: str, amount: int, task_id: str | None) -> None:
        posted = _whole("amount", amount)
        if posted <= 0 or not debit or not credit or debit == credit:
            raise ValueError("BILLING_AMOUNT_INVALID")
        self.journal.append(
            JournalEntry(
                kind=kind,
                task_id=task_id,
                legs=(JournalLeg(debit, -posted), JournalLeg(credit, posted)),
            )
        )

    def _wallet(self, wallet_id: str) -> WalletAccount:
        for wallet in self.wallets:
            if wallet.wallet_id == wallet_id:
                return wallet
        raise ValueError("BILLING_WALLET_MISSING")

    @staticmethod
    def _wallet_row(wallet: WalletAccount) -> dict[str, Any]:
        return {
            "id": wallet.wallet_id,
            "name": wallet.name,
            "availableFibonAtomic": wallet.available,
            "reservedFibonAtomic": wallet.reserved,
            "builtin": wallet.builtin,
        }


_books: dict[UUID, WorkspaceBook] = {}


def ensure_book(workspace_id: UUID, dev_workspace_ids: frozenset[UUID]) -> WorkspaceBook:
    found = _books.get(workspace_id)
    if found is not None:
        return found
    grant = 0
    if workspace_id in dev_workspace_ids:
        from edgemint.economy.fibonai_token import cached_economy

        grant = DEV_GRANT_TOKENS * cached_economy().atomic_units_per_token
    found = WorkspaceBook.open(workspace_id, grant_atomic=grant)
    _books[workspace_id] = found
    return found


def existing_book(workspace_id: UUID) -> WorkspaceBook | None:
    return _books.get(workspace_id)


def forget_book(workspace_id: UUID) -> None:
    _books.pop(workspace_id, None)


def detach_book(workspace_id: UUID) -> WorkspaceBook | None:
    return _books.pop(workspace_id, None)


def restore_book(workspace_id: UUID, book: WorkspaceBook | None) -> None:
    if book is None:
        _books.pop(workspace_id, None)
        return
    _books[workspace_id] = book


def install_book(book: WorkspaceBook) -> None:
    _books[book.workspace_id] = book


def _task_id(task_id: str) -> str:
    if not isinstance(task_id, str) or not task_id.strip():
        raise ValueError("BILLING_TASK_INVALID")
    return task_id


def _open_invoice(task_id: str, charge: int, now: str) -> dict[str, Any]:
    return {
        "id": f"inv_{task_id.removeprefix('tsk_')}",
        "status": "open",
        "amountFibonAtomic": charge,
        "taskId": task_id,
        "period": now[:7],
        "dueDate": now[:10],
        "createdAt": now,
    }


def _receipt(posting: TaskPosting, status: str) -> SettlementReceipt:
    return SettlementReceipt(
        task_id=posting.task_id,
        status=status,
        charge_atomic=posting.charge_atomic,
        worker_reward_atomic=posting.worker_reward_atomic,
        treasury_atomic=posting.treasury_atomic,
        slices=posting.slices,
    )
