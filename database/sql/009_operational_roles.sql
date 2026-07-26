BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'edgemint_migrator') THEN
    CREATE ROLE edgemint_migrator NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'edgemint_runtime') THEN
    CREATE ROLE edgemint_runtime NOLOGIN NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'edgemint_readonly') THEN
    CREATE ROLE edgemint_readonly NOLOGIN NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'edgemint_system_owner') THEN
    CREATE ROLE edgemint_system_owner NOLOGIN BYPASSRLS;
  END IF;
END
$$;

GRANT USAGE ON SCHEMA public, security, eventing, audit TO edgemint_runtime, edgemint_readonly;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public, eventing TO edgemint_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public, eventing TO edgemint_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA public, eventing, audit TO edgemint_readonly;

-- Cross-workspace queue/event functions execute through a narrowly scoped SECURITY DEFINER boundary.
ALTER FUNCTION public.post_ledger_transaction(uuid, varchar, varchar, varchar, varchar, char, varchar, varchar, jsonb)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.claim_outbox_batch(text, integer, integer, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.claim_websocket_deliveries(text, uuid, integer, integer, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.acknowledge_delivery(uuid, bigint, uuid)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.open_websocket_connection(varchar, uuid, uuid, varchar, varchar, bytea, timestamptz, varchar, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.create_websocket_subscription(varchar, uuid, uuid, uuid, jsonb)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.mark_websocket_delivery_sent(uuid, text, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.touch_websocket_connection(uuid, text, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION eventing.close_websocket_connection(uuid, text)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION public.select_next_routable_attempt(text, integer, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION public.acquire_assignment_lease(uuid, uuid, uuid, text, bytea, integer, integer, integer, integer, integer)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION public.start_auto_assigned_work(uuid, uuid, bigint, bytea, bigint, bigint)
  OWNER TO edgemint_system_owner;
ALTER FUNCTION public.renew_auto_assignment_lease(uuid, uuid, bigint, bytea, bigint, integer)
  OWNER TO edgemint_system_owner;

ALTER FUNCTION public.post_ledger_transaction(uuid, varchar, varchar, varchar, varchar, char, varchar, varchar, jsonb)
  SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION eventing.claim_outbox_batch(text, integer, integer, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.claim_websocket_deliveries(text, uuid, integer, integer, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.acknowledge_delivery(uuid, bigint, uuid)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.open_websocket_connection(varchar, uuid, uuid, varchar, varchar, bytea, timestamptz, varchar, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.create_websocket_subscription(varchar, uuid, uuid, uuid, jsonb)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.mark_websocket_delivery_sent(uuid, text, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.touch_websocket_connection(uuid, text, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION eventing.close_websocket_connection(uuid, text)
  SECURITY DEFINER SET search_path = pg_catalog, public, eventing;
ALTER FUNCTION public.select_next_routable_attempt(text, integer, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION public.acquire_assignment_lease(uuid, uuid, uuid, text, bytea, integer, integer, integer, integer, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION public.start_auto_assigned_work(uuid, uuid, bigint, bytea, bigint, bigint)
  SECURITY DEFINER SET search_path = pg_catalog, public;
ALTER FUNCTION public.renew_auto_assignment_lease(uuid, uuid, bigint, bytea, bigint, integer)
  SECURITY DEFINER SET search_path = pg_catalog, public;

REVOKE ALL ON FUNCTION public.post_ledger_transaction(uuid, varchar, varchar, varchar, varchar, char, varchar, varchar, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.claim_outbox_batch(text, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.claim_websocket_deliveries(text, uuid, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.acknowledge_delivery(uuid, bigint, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.open_websocket_connection(varchar, uuid, uuid, varchar, varchar, bytea, timestamptz, varchar, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.create_websocket_subscription(varchar, uuid, uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.mark_websocket_delivery_sent(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.touch_websocket_connection(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION eventing.close_websocket_connection(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.select_next_routable_attempt(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acquire_assignment_lease(uuid, uuid, uuid, text, bytea, integer, integer, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_auto_assigned_work(uuid, uuid, bigint, bytea, bigint, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.renew_auto_assignment_lease(uuid, uuid, bigint, bytea, bigint, integer) FROM PUBLIC;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public, eventing, security TO edgemint_runtime;

ALTER DEFAULT PRIVILEGES IN SCHEMA public, eventing
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO edgemint_runtime;
ALTER DEFAULT PRIVILEGES IN SCHEMA public, eventing
  GRANT USAGE, SELECT ON SEQUENCES TO edgemint_runtime;
ALTER DEFAULT PRIVILEGES IN SCHEMA public, eventing
  GRANT EXECUTE ON FUNCTIONS TO edgemint_runtime;

COMMIT;
