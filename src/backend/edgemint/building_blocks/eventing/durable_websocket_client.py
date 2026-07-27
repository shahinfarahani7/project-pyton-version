from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any


@dataclass(slots=True)
class InFlightLimiter:
    max_in_flight: int = 256
    _in_flight: int = 0
    _capacity_available: asyncio.Event = field(default_factory=asyncio.Event)

    def __post_init__(self) -> None:
        if self.can_accept():
            self._capacity_available.set()
        else:
            self._capacity_available.clear()

    def can_accept(self) -> bool:
        return self._in_flight < self.max_in_flight

    def reserve(self) -> None:
        if not self.can_accept():
            raise RuntimeError("IN_FLIGHT_LIMIT_EXCEEDED")
        self._in_flight += 1
        if not self.can_accept():
            self._capacity_available.clear()

    def release(self) -> None:
        if self._in_flight > 0:
            self._in_flight -= 1
        if self.can_accept():
            self._capacity_available.set()

    async def wait_for_capacity(self) -> None:
        while not self.can_accept():
            await self._capacity_available.wait()


EventHandler = Callable[[dict[str, Any]], Awaitable[None]]


@dataclass(slots=True)
class DurableWebSocketClient:
    """Reference consumer that enforces inbox-before-ack ordering and in-flight backpressure."""

    client_id: str
    client_version: str
    max_in_flight: int = 256
    _limiter: InFlightLimiter = field(init=False)
    _resume_token: str | None = None
    _seen_delivery_ids: set[str] = field(default_factory=set)

    def __post_init__(self) -> None:
        self._limiter = InFlightLimiter(max_in_flight=self.max_in_flight)

    def build_hello_frame(self, *, request_id: str) -> dict[str, Any]:
        frame: dict[str, Any] = {
            "type": "hello",
            "requestId": request_id,
            "clientId": self.client_id,
            "clientVersion": self.client_version,
        }
        if self._resume_token:
            frame["resumeToken"] = self._resume_token
        return frame

    def remember_resume_token(self, token: str) -> None:
        self._resume_token = token

    async def handle_event_frame(
        self,
        frame: dict[str, Any],
        *,
        on_process: EventHandler,
        on_ack: Callable[[dict[str, Any]], Awaitable[None]],
    ) -> None:
        delivery_id = str(frame["deliveryId"])
        if delivery_id in self._seen_delivery_ids:
            return
        self._limiter.reserve()
        try:
            await on_process(frame)
            await on_ack(
                {
                    "type": "ack",
                    "requestId": frame["requestId"],
                    "deliveryId": delivery_id,
                    "sequence": frame["sequence"],
                }
            )
            self._seen_delivery_ids.add(delivery_id)
        finally:
            self._limiter.release()

    async def wait_for_backpressure(self) -> None:
        await self._limiter.wait_for_capacity()
