from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.building_blocks.eventing.transactional_outbox import OutboxEvent, enqueue_outbox_event
from edgemint.building_blocks.ids import EntityId, public_id
from edgemint.building_blocks.settings import Settings, get_settings
from edgemint.files.idempotency import (
    begin_idempotent_command,
    complete_idempotent_command,
    idempotency_scope,
)
from edgemint.pricing.engine import PricingEngine
from edgemint.pricing.policy import load_price_policy
from edgemint.pricing.quotes import CreateQuoteRequest, QuoteService
from edgemint.security.context import AuthorizationContext
from edgemint.security.tokens import write_audit_event
from edgemint.tasks.catalog_closure import validate_queue_admission
from edgemint.tasks.errors import task_error
from edgemint.tasks.lifecycle import (
    CANCELLABLE_DB_STATUSES,
    REVISION_ELIGIBLE_DB_STATUSES,
    TaskLifecycle,
    map_db_execution_status,
    map_db_lifecycle_to_api,
    priority_mapping,
    task_type_to_api_code,
    task_type_to_catalog_code,
)
from edgemint.tasks.reservation import (
    count_active_draft_tasks,
    release_credit_reservation,
    reserve_credit,
)
from edgemint.tasks.schemas import CreateRevisionRequest, CreateTaskRequest, TaskResponse
from edgemint.routing.execution_allocation import ExecutionAllocationService, input_hints_from_task_input
from edgemint.security.workspace_data_trust import WorkspaceDataTrustService
from edgemint.tasks.task_run import TaskRunService, compute_input_digest
from edgemint.files.input_decode_bounds import evaluate_decode_admission
from edgemint.tasks.validation import (
    TaskTypeContract,
    load_task_type_contracts,
    validate_configuration_parameters,
    validate_task_submission,
)


@dataclass
class TaskAdmissionService:
    settings: Settings = field(default_factory=get_settings)
    lifecycle: TaskLifecycle = field(default_factory=TaskLifecycle.load)
    pricing: PricingEngine = field(default_factory=lambda: PricingEngine(load_price_policy()))
    quotes: QuoteService = field(default_factory=QuoteService.default)
    task_runs: TaskRunService = field(default_factory=TaskRunService)
    execution_allocations: ExecutionAllocationService = field(default_factory=ExecutionAllocationService)
    data_trust: WorkspaceDataTrustService = field(default_factory=WorkspaceDataTrustService)

    async def create_task(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        payload: CreateTaskRequest,
        idempotency_key: str,
    ) -> TaskResponse:
        if auth.workspace_id != payload.workspaceId:
            raise task_error("TENANT_RESOURCE_NOT_FOUND", detail="workspace mismatch")
        if not payload.input.fileId and not payload.input.inlineText:
            raise task_error("INPUT_SCHEMA_INVALID", detail="input.fileId or input.inlineText required")
        if payload.input.fileId and not payload.input.contentType:
            raise task_error("INPUT_SCHEMA_INVALID", detail="input.contentType required for file tasks")

        catalog_code = task_type_to_catalog_code(payload.taskType)
        validate_queue_admission(
            catalog_code=catalog_code,
            mode=self.settings.catalog_closure_mode,  # type: ignore[arg-type]
        )

        contract_catalog = load_task_type_contracts()
        if payload.taskType in contract_catalog:
            contract = validate_task_submission(
                api_task_type=payload.taskType,
                content_type=payload.input.contentType or "text/plain",
                contracts=contract_catalog,
            )
        else:
            contract = TaskTypeContract(
                code=catalog_code,
                status="active",
                allowed_content_types=frozenset(),
                maximum_bytes=self.settings.file_max_upload_bytes,
            )
        validate_configuration_parameters(payload.taskType, payload.configuration.parameters)
        trust = await self.data_trust.assert_task_admission_permitted(
            connection,
            workspace_id=auth.workspace_id,
        )
        if not trust.permitted:
            raise task_error("DATA_PROCESSING_DENIED", detail=trust.reason)
        draft_count = await count_active_draft_tasks(connection, workspace_id=auth.workspace_id)
        if draft_count >= self.settings.task_admission_max_drafts:
            raise task_error("ADMISSION_LIMIT_EXCEEDED")

        scope = idempotency_scope(
            operation_id="createTask",
            principal_id=auth.principal.principal_id,
            workspace_id=auth.workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload=payload.model_dump(mode="json"),
        )
        if replay is not None:
            if replay.status_code == 409:
                raise task_error("IDEMPOTENCY_CONFLICT")
            return TaskResponse.model_validate(replay.body)

        input_file_id: UUID | None = None
        if payload.input.fileId:
            file_row = await self._load_file(
                connection,
                workspace_id=auth.workspace_id,
                file_public_id=payload.input.fileId,
            )
            if file_row is None:
                raise task_error("TENANT_RESOURCE_NOT_FOUND", detail="file not found")
            if str(file_row["status"]) != "ready":
                raise task_error("FILE_NOT_READY")
            self._assert_file_decode_bounds(
                file_row=file_row,
                payload=payload,
                contract=contract,
            )
            input_file_id = UUID(str(file_row["id"]))

        task_entity = EntityId.new()
        task_public = public_id("tsk")
        revision_entity = EntityId.new()
        revision_public = public_id("rev")
        priority_class, priority_bps = priority_mapping(payload.configuration.priority)
        created_at = datetime.now(UTC)
        parameters_json = json.dumps(
            {
                "configuration": payload.configuration.model_dump(mode="json"),
                "metadata": payload.metadata,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
        input_digest = compute_input_digest(
            inline_text=payload.input.inlineText,
            parameters_json=parameters_json,
            input_file_id=input_file_id,
        )

        await connection.execute(
            text(
                """
                INSERT INTO public.tasks(
                    id, workspace_id, public_id, task_type, lifecycle_status,
                    idempotency_key, priority_class, priority_bps, submitted_at_utc
                )
                VALUES (
                    :id, :workspace_id, :public_id, :task_type, 'submitted',
                    :idempotency_key, :priority_class, :priority_bps, :submitted_at_utc
                )
                """
            ),
            {
                "id": task_entity.value,
                "workspace_id": auth.workspace_id,
                "public_id": task_public,
                "task_type": contract.code,
                "idempotency_key": idempotency_key,
                "priority_class": priority_class,
                "priority_bps": priority_bps,
                "submitted_at_utc": created_at,
            },
        )
        await connection.execute(
            text(
                """
                INSERT INTO public.task_revisions(
                    id, workspace_id, public_id, task_id, revision_number, input_file_id,
                    inline_text, parameters_json, submitted_at_utc
                )
                VALUES (
                    :id, :workspace_id, :public_id, :task_id, 1, :input_file_id,
                    :inline_text, CAST(:parameters_json AS jsonb), :submitted_at_utc
                )
                """
            ),
            {
                "id": revision_entity.value,
                "workspace_id": auth.workspace_id,
                "public_id": revision_public,
                "task_id": task_entity.value,
                "input_file_id": input_file_id,
                "inline_text": payload.input.inlineText,
                "parameters_json": parameters_json,
                "submitted_at_utc": created_at,
            },
        )
        await connection.execute(
            text(
                """
                UPDATE public.tasks
                SET current_revision_id = :revision_id,
                    lifecycle_status = 'queued',
                    updated_at_utc = :updated_at_utc
                WHERE id = :task_id AND workspace_id = :workspace_id
                """
            ),
            {
                "revision_id": revision_entity.value,
                "task_id": task_entity.value,
                "workspace_id": auth.workspace_id,
                "updated_at_utc": created_at,
            },
        )
        task_run_id = await self.task_runs.create_for_admitted_task(
            connection,
            workspace_id=auth.workspace_id,
            task_id=task_entity.value,
            task_revision_id=revision_entity.value,
            client_request_key=idempotency_key,
            input_digest=input_digest,
        )
        await self.execution_allocations.create_for_task_run(
            connection,
            workspace_id=auth.workspace_id,
            task_run_id=task_run_id,
            task_revision_id=revision_entity.value,
            input_digest=input_digest,
            task_type=contract.code,
            hints=input_hints_from_task_input(
                inline_text=payload.input.inlineText,
                input_payload=payload.input.model_dump(mode="json"),
            ),
        )

        quote_id, quote_amount, quote_expires = await self._resolve_quote(
            connection,
            auth=auth,
            payload=payload,
            task_id=task_entity.value,
            revision_id=revision_entity.value,
        )
        await reserve_credit(
            connection,
            workspace_id=auth.workspace_id,
            task_id=task_entity.value,
            task_revision_id=revision_entity.value,
            quote_id=quote_id,
            amount_micro_eur=quote_amount,
            expires_at=quote_expires,
        )

        for event_type, aggregate_sequence in [
            ("task.created", 1),
            ("credit.reserved", 2),
            ("task.queued", 3),
        ]:
            await enqueue_outbox_event(
                connection,
                OutboxEvent(
                    event_type=event_type,
                    aggregate_type="task",
                    aggregate_id=task_public,
                    aggregate_sequence=aggregate_sequence,
                    cloud_event={
                        "specversion": "1.0",
                        "type": f"io.edgemint.{event_type}.v1",
                        "source": "edgemint.task-intake",
                        "id": task_public,
                        "time": created_at.isoformat(),
                        "data": {
                            "taskId": task_public,
                            "revisionId": revision_public,
                            "workspaceId": str(auth.workspace_id),
                        },
                    },
                    workspace_id=auth.workspace_id,
                ),
            )

        await write_audit_event(
            connection,
            workspace_id=auth.workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="task.created",
            resource_type="task",
            resource_id=task_public,
            details={"taskType": payload.taskType, "quoteId": str(quote_id)},
        )

        response = TaskResponse(
            id=task_public,
            workspaceId=str(auth.workspace_id),
            taskType=payload.taskType,
            currentRevisionId=revision_public,
            createdAt=created_at,
            version=1,
            lifecycleStatus="submitted",
            executionStatus="queued",
            billingStatus="reserved",
        )
        await complete_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=202,
            body=response.model_dump(mode="json"),
        )
        return response

    async def create_revision(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        task_public_id: str,
        payload: CreateRevisionRequest,
        idempotency_key: str,
    ) -> TaskResponse:
        if not payload.changeReason.strip():
            raise task_error("CHANGE_REASON_REQUIRED")
        task = await self._load_task(
            connection,
            workspace_id=auth.workspace_id,
            task_public_id=task_public_id,
        )
        if task is None:
            raise task_error("TENANT_RESOURCE_NOT_FOUND")
        if str(task["lifecycle_status"]) not in REVISION_ELIGIBLE_DB_STATUSES:
            raise task_error("TASK_REVISION_IMMUTABLE", detail=str(task["lifecycle_status"]))

        scope = idempotency_scope(
            operation_id="createTaskRevision",
            principal_id=auth.principal.principal_id,
            workspace_id=auth.workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload={"taskId": task_public_id, **payload.model_dump(mode="json")},
        )
        if replay is not None:
            if replay.status_code == 409:
                raise task_error("IDEMPOTENCY_CONFLICT")
            return TaskResponse.model_validate(replay.body)

        api_task_type = task_type_to_api_code(str(task["task_type"]))
        validate_queue_admission(
            catalog_code=str(task["task_type"]),
            mode=self.settings.catalog_closure_mode,  # type: ignore[arg-type]
        )
        contract_catalog = load_task_type_contracts()
        if api_task_type in contract_catalog:
            contract = validate_task_submission(
                api_task_type=api_task_type,
                content_type=payload.input.contentType or "text/plain",
                contracts=contract_catalog,
            )
        else:
            contract = TaskTypeContract(
                code=str(task["task_type"]),
                status="active",
                allowed_content_types=frozenset(),
                maximum_bytes=self.settings.file_max_upload_bytes,
            )
        validate_configuration_parameters(api_task_type, payload.configuration.parameters)

        input_file_id: UUID | None = None
        if payload.input.fileId:
            file_row = await self._load_file(
                connection,
                workspace_id=auth.workspace_id,
                file_public_id=payload.input.fileId,
            )
            if file_row is None:
                raise task_error("TENANT_RESOURCE_NOT_FOUND", detail="file not found")
            if str(file_row["status"]) != "ready":
                raise task_error("FILE_NOT_READY")
            self._assert_file_decode_bounds(
                file_row=file_row,
                payload=payload,
                contract=contract,
            )
            input_file_id = UUID(str(file_row["id"]))

        revision_number = int(task["revision_count"]) + 1
        revision_entity = EntityId.new()
        revision_public = public_id("rev")
        updated_at = datetime.now(UTC)

        await connection.execute(
            text(
                """
                INSERT INTO public.task_revisions(
                    id, workspace_id, public_id, task_id, revision_number, input_file_id,
                    inline_text, parameters_json, submitted_at_utc
                )
                VALUES (
                    :id, :workspace_id, :public_id, :task_id, :revision_number, :input_file_id,
                    :inline_text, CAST(:parameters_json AS jsonb), :submitted_at_utc
                )
                """
            ),
            {
                "id": revision_entity.value,
                "workspace_id": auth.workspace_id,
                "public_id": revision_public,
                "task_id": task["id"],
                "revision_number": revision_number,
                "input_file_id": input_file_id,
                "inline_text": payload.input.inlineText,
                "parameters_json": json.dumps(
                    {
                        "configuration": payload.configuration.model_dump(mode="json"),
                        "changeReason": payload.changeReason,
                    },
                    separators=(",", ":"),
                    sort_keys=True,
                ),
                "submitted_at_utc": updated_at,
            },
        )
        await connection.execute(
            text(
                """
                UPDATE public.tasks
                SET current_revision_id = :revision_id,
                    lifecycle_status = 'queued',
                    updated_at_utc = :updated_at_utc
                WHERE id = :task_id AND workspace_id = :workspace_id
                """
            ),
            {
                "revision_id": revision_entity.value,
                "task_id": task["id"],
                "workspace_id": auth.workspace_id,
                "updated_at_utc": updated_at,
            },
        )
        await enqueue_outbox_event(
            connection,
            OutboxEvent(
                event_type="task.revision.created",
                aggregate_type="task",
                aggregate_id=task_public_id,
                aggregate_sequence=revision_number,
                cloud_event={
                    "specversion": "1.0",
                    "type": "io.edgemint.task.revision.created.v1",
                    "source": "edgemint.task-intake",
                    "id": revision_public,
                    "time": updated_at.isoformat(),
                    "data": {
                        "taskId": task_public_id,
                        "revisionId": revision_public,
                        "changeReason": payload.changeReason,
                    },
                },
                workspace_id=auth.workspace_id,
            ),
        )
        await write_audit_event(
            connection,
            workspace_id=auth.workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="task.revision.created",
            resource_type="task",
            resource_id=task_public_id,
            details={"revisionId": revision_public, "changeReason": payload.changeReason},
        )

        response = TaskResponse(
            id=task_public_id,
            workspaceId=str(auth.workspace_id),
            taskType=api_task_type,
            currentRevisionId=revision_public,
            createdAt=task["created_at_utc"],
            version=revision_number,
            lifecycleStatus="submitted",
            executionStatus="queued",
            billingStatus="reserved",
        )
        await complete_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=202,
            body=response.model_dump(mode="json"),
        )
        return response

    async def cancel_task(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        task_public_id: str,
        idempotency_key: str,
    ) -> TaskResponse:
        task = await self._load_task(
            connection,
            workspace_id=auth.workspace_id,
            task_public_id=task_public_id,
        )
        if task is None:
            raise task_error("TENANT_RESOURCE_NOT_FOUND")
        current = str(task["lifecycle_status"])
        if current not in CANCELLABLE_DB_STATUSES:
            raise task_error("TASK_NOT_CANCELLABLE", detail=current)
        self.lifecycle.assert_transition(map_db_lifecycle_to_api(current), "cancelled")

        scope = idempotency_scope(
            operation_id="cancelTask",
            principal_id=auth.principal.principal_id,
            workspace_id=auth.workspace_id,
        )
        replay = await begin_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            payload={"taskId": task_public_id},
        )
        if replay is not None:
            if replay.status_code == 409:
                raise task_error("IDEMPOTENCY_CONFLICT")
            return TaskResponse.model_validate(replay.body)

        updated_at = datetime.now(UTC)
        await self.task_runs.cancel_open_runs_for_task(
            connection,
            workspace_id=auth.workspace_id,
            task_id=UUID(str(task["id"])),
        )
        await connection.execute(
            text(
                """
                UPDATE public.tasks
                SET lifecycle_status = 'cancelled',
                    updated_at_utc = :updated_at_utc
                WHERE id = :task_id AND workspace_id = :workspace_id
                """
            ),
            {
                "task_id": task["id"],
                "workspace_id": auth.workspace_id,
                "updated_at_utc": updated_at,
            },
        )
        await release_credit_reservation(
            connection,
            workspace_id=auth.workspace_id,
            task_id=UUID(str(task["id"])),
        )
        for event_type in ("credit.released", "task.cancelled"):
            await enqueue_outbox_event(
                connection,
                OutboxEvent(
                    event_type=event_type,
                    aggregate_type="task",
                    aggregate_id=task_public_id,
                    aggregate_sequence=1,
                    cloud_event={
                        "specversion": "1.0",
                        "type": f"io.edgemint.{event_type}.v1",
                        "source": "edgemint.task-intake",
                        "id": task_public_id,
                        "time": updated_at.isoformat(),
                        "data": {"taskId": task_public_id},
                    },
                    workspace_id=auth.workspace_id,
                ),
            )
        await write_audit_event(
            connection,
            workspace_id=auth.workspace_id,
            actor_id=str(auth.principal.principal_id),
            action="task.cancelled",
            resource_type="task",
            resource_id=task_public_id,
            details={},
        )

        response = TaskResponse(
            id=task_public_id,
            workspaceId=str(auth.workspace_id),
            taskType=task_type_to_api_code(str(task["task_type"])),
            currentRevisionId=str(task["revision_public_id"]),
            createdAt=task["created_at_utc"],
            version=int(task["revision_count"]),
            lifecycleStatus="cancelled",
            executionStatus=map_db_execution_status("cancelled"),
            billingStatus="released",
        )
        await complete_idempotent_command(
            connection,
            workspace_id=auth.workspace_id,
            scope=scope,
            idempotency_key=idempotency_key,
            status_code=202,
            body=response.model_dump(mode="json"),
        )
        return response

    async def get_task(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        task_public_id: str,
    ) -> TaskResponse:
        task = await self._load_task(
            connection,
            workspace_id=auth.workspace_id,
            task_public_id=task_public_id,
        )
        if task is None:
            raise task_error("TENANT_RESOURCE_NOT_FOUND")
        billing = "reserved"
        reservation = (
            await connection.execute(
                text(
                    """
                    SELECT status
                    FROM public.credit_reservations
                    WHERE workspace_id = :workspace_id
                      AND task_id = :task_id
                    ORDER BY created_at_utc DESC
                    LIMIT 1
                    """
                ),
                {"workspace_id": auth.workspace_id, "task_id": task["id"]},
            )
        ).scalar_one_or_none()
        if reservation == "released" or str(task["lifecycle_status"]) == "cancelled":
            billing = "released"
        return TaskResponse(
            id=task_public_id,
            workspaceId=str(auth.workspace_id),
            taskType=task_type_to_api_code(str(task["task_type"])),
            currentRevisionId=str(task["revision_public_id"]),
            createdAt=task["created_at_utc"],
            version=int(task["revision_count"]),
            lifecycleStatus=map_db_lifecycle_to_api(str(task["lifecycle_status"])),
            executionStatus=map_db_execution_status(str(task["lifecycle_status"])),
            billingStatus=billing,
        )

    async def _resolve_quote(
        self,
        connection: AsyncConnection,
        *,
        auth: AuthorizationContext,
        payload: CreateTaskRequest,
        task_id: UUID,
        revision_id: UUID,
    ) -> tuple[UUID, int, datetime]:
        if payload.quoteId:
            quote = await self._load_quote(
                connection,
                workspace_id=auth.workspace_id,
                quote_public_id=payload.quoteId,
            )
            if quote is None:
                raise task_error("TENANT_RESOURCE_NOT_FOUND", detail="quote not found")
            expires_at = quote["expires_at_utc"]
            if expires_at < datetime.now(UTC):
                raise task_error("QUOTE_EXPIRED")
            if UUID(str(quote["task_revision_id"])) != revision_id:
                await connection.execute(
                    text(
                        """
                        UPDATE public.quotes
                        SET task_revision_id = :revision_id
                        WHERE id = :quote_id AND workspace_id = :workspace_id
                        """
                    ),
                    {
                        "revision_id": revision_id,
                        "quote_id": quote["id"],
                        "workspace_id": auth.workspace_id,
                    },
                )
            return UUID(str(quote["id"])), int(quote["amount_micro_eur"]), expires_at

        quote_request = CreateQuoteRequest(
            workspaceId=payload.workspaceId,
            taskType=payload.taskType,
            input=payload.input.model_dump(mode="json"),
            configuration=payload.configuration,
            quantity=1,
            plan="developer",
            region="eu-central",
            executionPolicy="edge_preferred",
            retention="default",
        )
        price_input = self.quotes.build_price_input(quote_request)
        price = self.pricing.quote(price_input)
        price_book_id = await self._ensure_price_book(connection)
        quote_entity = EntityId.new()
        quote_public = public_id("qte")
        expires_at = datetime.now(UTC) + timedelta(seconds=self.pricing.policy.quote_ttl_seconds)
        await connection.execute(
            text(
                """
                INSERT INTO public.quotes(
                    id, workspace_id, public_id, task_revision_id,
                    price_book_id, amount_micro_eur, expires_at_utc
                )
                VALUES (
                    :id, :workspace_id, :public_id, :task_revision_id,
                    :price_book_id, :amount_micro_eur, :expires_at_utc
                )
                """
            ),
            {
                "id": quote_entity.value,
                "workspace_id": auth.workspace_id,
                "public_id": quote_public,
                "task_revision_id": revision_id,
                "price_book_id": price_book_id,
                "amount_micro_eur": price.charge_micros,
                "expires_at_utc": expires_at,
            },
        )
        return quote_entity.value, price.charge_micros, expires_at

    async def _ensure_price_book(self, connection: AsyncConnection) -> UUID:
        version = self.pricing.policy.version_label
        existing = (
            await connection.execute(
                text("SELECT id FROM public.price_books WHERE version = :version LIMIT 1"),
                {"version": version},
            )
        ).scalar_one_or_none()
        if existing is not None:
            return UUID(str(existing))
        book_id = EntityId.new().value
        await connection.execute(
            text(
                """
                INSERT INTO public.price_books(
                    id, version, currency, status, effective_at_utc, rules_json
                )
                VALUES (
                    :id, :version, 'EUR', 'active', CURRENT_TIMESTAMP,
                    CAST('{}' AS jsonb)
                )
                """
            ),
            {"id": book_id, "version": version},
        )
        return book_id

    async def _load_file(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        file_public_id: str,
    ) -> dict[str, Any] | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, status, content_type, size_bytes
                    FROM public.files
                    WHERE workspace_id = :workspace_id AND public_id = :public_id
                    LIMIT 1
                    """
                ),
                {"workspace_id": workspace_id, "public_id": file_public_id},
            )
        ).mappings().first()
        return dict(row) if row is not None else None

    def _assert_file_decode_bounds(
        self,
        *,
        file_row: dict[str, Any],
        payload: CreateTaskRequest | CreateRevisionRequest,
        contract: TaskTypeContract,
    ) -> None:
        content_type = payload.input.contentType or str(file_row.get("content_type") or "application/octet-stream")
        page_count = int(payload.configuration.parameters.get("pageCount") or 1)
        image_meta = payload.configuration.parameters.get("image")
        image_width = int(image_meta.get("width") or 0) if isinstance(image_meta, dict) else 0
        image_height = int(image_meta.get("height") or 0) if isinstance(image_meta, dict) else 0
        decode = evaluate_decode_admission(
            content_type=content_type,
            compressed_bytes=int(file_row.get("size_bytes") or contract.maximum_bytes),
            page_count=page_count,
            image_width=image_width,
            image_height=image_height,
        )
        if not decode.permitted:
            raise task_error(decode.reason_code.value, detail=decode.detail)

    async def _load_quote(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        quote_public_id: str,
    ) -> dict[str, Any] | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT id, task_revision_id, amount_micro_eur, expires_at_utc
                    FROM public.quotes
                    WHERE workspace_id = :workspace_id
                      AND (public_id = :public_id OR id::text = :public_id)
                    LIMIT 1
                    """
                ),
                {"workspace_id": workspace_id, "public_id": quote_public_id},
            )
        ).mappings().first()
        return dict(row) if row is not None else None

    async def _load_task(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        task_public_id: str,
    ) -> dict[str, Any] | None:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT
                        task.id,
                        task.task_type,
                        task.lifecycle_status,
                        task.created_at_utc,
                        revision.public_id AS revision_public_id,
                        (
                            SELECT COUNT(*)
                            FROM public.task_revisions AS rev
                            WHERE rev.task_id = task.id
                              AND rev.workspace_id = task.workspace_id
                        ) AS revision_count
                    FROM public.tasks AS task
                    JOIN public.task_revisions AS revision
                      ON revision.id = task.current_revision_id
                     AND revision.workspace_id = task.workspace_id
                    WHERE task.workspace_id = :workspace_id
                      AND task.public_id = :public_id
                    LIMIT 1
                    """
                ),
                {"workspace_id": workspace_id, "public_id": task_public_id},
            )
        ).mappings().first()
        return dict(row) if row is not None else None
