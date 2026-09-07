from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from edgemint.security.data_policy_registry import ExecutionPolicyId, data_policy_ref
from edgemint.security.tenant_data_trust import DataTrustDecision, evaluate_processing_permission


@dataclass(frozen=True, slots=True)
class WorkspaceDataTrustContext:
    workspace_id: UUID
    data_policy_ref: str
    default_execution_policy: ExecutionPolicyId
    cloud_fallback_allowed: bool
    data_region: str


class WorkspaceDataTrustService:
    async def load_context(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
    ) -> WorkspaceDataTrustContext:
        row = (
            await connection.execute(
                text(
                    """
                    SELECT binding.data_policy_ref,
                           binding.default_execution_policy,
                           binding.cloud_fallback_allowed,
                           binding.data_region
                    FROM public.workspace_data_policy_bindings AS binding
                    WHERE binding.workspace_id = :workspace_id
                    """
                ),
                {"workspace_id": workspace_id},
            )
        ).mappings().first()
        if row is not None:
            return WorkspaceDataTrustContext(
                workspace_id=workspace_id,
                data_policy_ref=str(row["data_policy_ref"]),
                default_execution_policy=str(row["default_execution_policy"]),  # type: ignore[arg-type]
                cloud_fallback_allowed=bool(row["cloud_fallback_allowed"]),
                data_region=str(row["data_region"]),
            )
        workspace = (
            await connection.execute(
                text("SELECT data_region FROM public.workspaces WHERE id = :workspace_id"),
                {"workspace_id": workspace_id},
            )
        ).mappings().first()
        data_region = str(workspace["data_region"]) if workspace is not None else "eu-central"
        return WorkspaceDataTrustContext(
            workspace_id=workspace_id,
            data_policy_ref=data_policy_ref(),
            default_execution_policy="edge_preferred",
            cloud_fallback_allowed=True,
            data_region=data_region,
        )

    async def assert_task_admission_permitted(
        self,
        connection: AsyncConnection,
        *,
        workspace_id: UUID,
        execution_policy: ExecutionPolicyId | None = None,
        data_owner_consent_granted: bool = True,
    ) -> DataTrustDecision:
        context = await self.load_context(connection, workspace_id=workspace_id)
        policy_execution = execution_policy or context.default_execution_policy
        return evaluate_processing_permission(
            execution_policy=policy_execution,
            destination="edge_worker",
            data_region=context.data_region,
            data_owner_consent_granted=data_owner_consent_granted,
        )
