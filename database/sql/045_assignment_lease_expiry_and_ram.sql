-- Unknown free RAM must not be stored as a fabricated capacity.
-- NULL fails `free_ram_bytes >= minimum`, so an unmeasured device is not selected.

BEGIN;

ALTER TABLE public.worker_heartbeats
  ALTER COLUMN free_ram_bytes DROP NOT NULL;

-- Releases leased/running assignments whose lease has elapsed even when the
-- worker process never comes back. Terminal rows are left untouched.
-- A task that is still running is returned to queued when the attempt number
-- is still inside the default budget; otherwise the task is expired.
-- This does not create a new attempt. The router owns the next lease.
CREATE OR REPLACE FUNCTION public.expire_elapsed_assignment_leases()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  expired_row record;
  expired_count integer := 0;
BEGIN
  FOR expired_row IN
    SELECT
      assignment.id AS assignment_id,
      assignment.workspace_id,
      assignment.task_attempt_id,
      task.id AS task_id,
      task.lifecycle_status,
      attempt.attempt_number,
      attempt.status AS attempt_status
    FROM public.assignments AS assignment
    JOIN public.task_attempts AS attempt
      ON attempt.id = assignment.task_attempt_id
     AND attempt.workspace_id = assignment.workspace_id
    JOIN public.tasks AS task
      ON task.id = attempt.task_id
     AND task.workspace_id = attempt.workspace_id
    WHERE assignment.status IN ('leased', 'running')
      AND assignment.lease_expires_at_utc <= CURRENT_TIMESTAMP
    FOR UPDATE OF assignment
  LOOP
    UPDATE public.assignments
    SET status = 'expired',
        ended_at_utc = CURRENT_TIMESTAMP,
        failure_reason_code = 'LEASE_EXPIRED'
    WHERE id = expired_row.assignment_id
      AND status IN ('leased', 'running');

    PERFORM public.release_worker_resource_reservation_by_assignment(
      expired_row.assignment_id,
      'expired'
    );

    DELETE FROM public.assignment_lease_credentials
    WHERE assignment_id = expired_row.assignment_id;

    IF expired_row.lifecycle_status IN ('running', 'assigned') THEN
      IF expired_row.attempt_number >= 3 THEN
        UPDATE public.tasks
        SET lifecycle_status = 'expired',
            updated_at_utc = CURRENT_TIMESTAMP
        WHERE id = expired_row.task_id
          AND workspace_id = expired_row.workspace_id
          AND lifecycle_status IN ('running', 'assigned');
      ELSE
        UPDATE public.tasks
        SET lifecycle_status = 'queued',
            updated_at_utc = CURRENT_TIMESTAMP
        WHERE id = expired_row.task_id
          AND workspace_id = expired_row.workspace_id
          AND lifecycle_status IN ('running', 'assigned');
        UPDATE public.task_attempts
        SET status = 'queued',
            completed_at_utc = NULL
        WHERE id = expired_row.task_attempt_id
          AND workspace_id = expired_row.workspace_id
          AND status IN ('running', 'assigned', 'leased');
      END IF;
    END IF;

    expired_count := expired_count + 1;
  END LOOP;

  RETURN expired_count;
END
$$;

COMMIT;
