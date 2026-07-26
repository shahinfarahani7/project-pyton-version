#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
files=sorted((ROOT/'database/sql').glob('*.sql'));errors=[];sql='\n'.join(p.read_text() for p in files)
if len(files)!=9:errors.append(f'expected 9 ordered PostgreSQL migrations, got {len(files)}')
for i,p in enumerate(files,1):
 if not p.name.startswith(f'{i:03d}_'):errors.append(f'non-contiguous migration:{p.name}')
 if re.search(r'\b(DROP TABLE|TRUNCATE TABLE)\b',p.read_text(),re.I):errors.append(f'destructive statement:{p.name}')
for bad in ['uniqueidentifier','nvarchar','datetime2','SYSUTCDATETIME','NEWSEQUENTIALID','OBJECT_ID','COL_LENGTH','CREATE SECURITY POLICY','SESSION_CONTEXT','sp_getapplock','OPENJSON','SQLCMDPASSWORD','dbo.','[UPDLOCK]','READPAST','ROWLOCK']:
 if bad.lower() in sql.lower():errors.append('SQL Server syntax remains:'+bad)
for token in ['CREATE EXTENSION IF NOT EXISTS pgcrypto','uuidv7()','jsonb','timestamptz','LANGUAGE plpgsql','ENABLE ROW LEVEL SECURITY','FORCE ROW LEVEL SECURITY','FOR UPDATE SKIP LOCKED','post_ledger_transaction','LEDGER_INVARIANT_FAILED','select_next_routable_attempt','acquire_assignment_lease','start_auto_assigned_work','renew_auto_assignment_lease','claim_outbox_batch','claim_websocket_deliveries','acknowledge_delivery','ux_active_assignment_per_attempt']:
 if token.lower() not in sql.lower():errors.append('required PostgreSQL invariant missing:'+token)
for stale in ['claim_expires_at_utc','claim_owner','occurred_at_utc','websocket_connection_id','lease_renewal_sequence','ledger_transaction_id','amount_micros']:
 if re.search(r'\b'+re.escape(stale)+r'\b',sql,re.I):errors.append('stale converted-column reference:'+stale)
for token in ['open_websocket_connection','create_websocket_subscription','mark_websocket_delivery_sent','touch_websocket_connection','close_websocket_connection','SECURITY DEFINER','BYPASSRLS','uuidv7()']:
 if token.lower() not in sql.lower():errors.append('required PostgreSQL security/event control missing:'+token)
for token in ['LEDGER_REQUIRES_TWO_DISTINCT_ACCOUNTS','LEDGER_REQUIRES_TWO_POSTED_ENTRIES','WEBSOCKET_WORKSPACE_ACCESS_DENIED','JOIN public.workspace_members']:
 if token.lower() not in sql.lower():errors.append('final audit invariant missing:'+token)
required=['organizations','workspaces','workspace_members','workspace_invitations','principals','api_credentials','files','file_upload_sessions','tasks','task_revisions','task_attempts','task_state_history','assignments','assignment_checkpoints','workers','worker_devices','worker_sessions','worker_consents','worker_preferences','worker_benchmarks','worker_heartbeats','device_challenges','models','model_versions','model_downloads','device_model_installs','model_rollouts','results','verifications','verification_votes','quotes','price_books','subscriptions','invoices','entitlement_snapshots','ledger_accounts','ledger_transactions','ledger_entries','usage_events','credit_reservations','reward_accruals','reward_claims','token_conversion_epochs','claim_batches','claim_batch_items','promotion_reservations','webhook_endpoints','webhook_deliveries','disputes','fraud_cases','security_incidents','policy_documents','policy_activations','reconciliation_runs','feature_flags','idempotency_records','outbox_events','inbox_events','audit_events','payout_accounts','payout_batches','payout_transfers','provider_webhook_events','websocket_connections','websocket_subscriptions','websocket_deliveries','websocket_acknowledgements','event_dead_letters','event_consumer_offsets','outbox_dead_letters','browser_sessions','delegated_token_jtis','system_audit_events','workspace_routing_fairness']
for t in required:
 if not re.search(r'CREATE TABLE IF NOT EXISTS\s+(?:public|eventing|security|audit)\.'+re.escape(t)+r'\b',sql,re.I):errors.append('missing table:'+t)
rls_tables=set(re.findall(r'CREATE POLICY\s+([a-z0-9_]+)_workspace_policy',sql,re.I))
if len(rls_tables)<29:errors.append(f'expected at least 29 RLS tables, got {len(rls_tables)}')
for t in ['tasks','task_revisions','task_attempts','assignments','results','quotes','ledger_accounts','ledger_transactions','ledger_entries','workspace_routing_fairness']:
 if t not in rls_tables:errors.append('workspace RLS policy missing:'+t)
for token in ['FOREIGN KEY(task_id,workspace_id)','FOREIGN KEY(task_revision_id,workspace_id)','FOREIGN KEY(task_attempt_id,workspace_id)','FOREIGN KEY(assignment_id,workspace_id)','FOREIGN KEY(result_id,workspace_id)','FOREIGN KEY(input_file_id,workspace_id)','FOREIGN KEY(output_file_id,workspace_id)']:
 if token.replace(' ','').lower() not in sql.replace(' ','').lower():errors.append('composite workspace foreign key missing:'+token)
for table in ['quotes','ledger_entries','usage_events','credit_reservations','reward_accruals','reward_claims','invoices','promotion_reservations','payout_transfers']:
 m=re.search(r'CREATE TABLE IF NOT EXISTS public\.'+table+r'\s*\((.*?)\n\);',sql,re.I|re.S)
 if m and re.search(r'\b(real|double precision|numeric|decimal|money)\b',m.group(1),re.I):errors.append('non-integral money type:'+table)
db=(ROOT/'src/backend/edgemint/building_blocks/database.py').read_text()
for token in ["set_config('app.workspace_id'",'isolation_level','connection.begin','pool_pre_ping']:
 if token not in db:errors.append('PostgreSQL transaction/RLS context control missing:'+token)
runner=(ROOT/'tools/run_postgresql_migrations.sh').read_text()
for token in ['sha256sum','psql -X','ON_ERROR_STOP','schema_migrations','MIGRATION_CHECKSUM_MISMATCH','PGPASSWORD','MIGRATION_MUST_END_WITH_COMMIT','commit atomically']:
 if token not in runner:errors.append('migration runner control missing:'+token)
print(json.dumps({'status':'passed' if not errors else 'failed','engine':'PostgreSQL 18','migrations':len(files),'tables':len(required),'rlsTables':len(rls_tables),'errors':errors},indent=2));sys.exit(1 if errors else 0)
