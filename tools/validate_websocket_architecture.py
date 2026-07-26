#!/usr/bin/env python3
from pathlib import Path
import json,re,sys,yaml
ROOT=Path(__file__).resolve().parents[1];errors=[]
canon=yaml.safe_load((ROOT/'production/canonical-decisions.yaml').read_text())['spec'];platform=canon['platform'];events=canon['events']
if platform.get('database')!='PostgreSQL 18 only':errors.append('canonical database is not PostgreSQL only')
if platform.get('realtimeTransport')!='Secure WebSocket only':errors.append('canonical transport is not secure WebSocket only')
if events.get('transport')!='wss' or events.get('endpoint')!='/events/v1':errors.append('canonical event endpoint mismatch')
paths=[ROOT/'production',ROOT/'cursor',ROOT/'contracts',ROOT/'database',ROOT/'deploy',ROOT/'src',ROOT/'compose.yaml',ROOT/'README.md',ROOT/'START-HERE.md']
banned=[r'\bkafka\b',r'\bamazon\s+msk\b',r'\brabbitmq\b',r'\bredpanda\b',r'\bredis\b',r'\belasticache\b',r'\bnpgsql\b',r'\bMicrosoft\.Data\.SqlClient\b']
for base in paths:
 files=[base] if base.is_file() else list(base.rglob('*'))
 for p in files:
  if not p.is_file() or p.name in {'CHECKSUMS.sha256','PACKAGE-MANIFEST.json'}:continue
  try:t=p.read_text()
  except:continue
  for pat in banned:
   if re.search(pat,t,re.I):errors.append(f'forbidden architecture token:{p.relative_to(ROOT)}:{pat}')
asyncapi=yaml.safe_load((ROOT/'contracts/asyncapi/edgemint-events.yaml').read_text());server=asyncapi['servers']['production']
if server.get('protocol')!='wss' or server.get('pathname')!='/events/v1':errors.append('AsyncAPI server is not WSS /events/v1')
if len(asyncapi.get('channels',{}))!=186 or len(asyncapi.get('components',{}).get('messages',{}))!=186:errors.append('AsyncAPI event coverage is not 186/186')
catalog=(ROOT/'src/backend/edgemint/services/event_catalog.py').read_text()
for event_name in asyncapi.get('channels',{}):
 if repr(event_name) not in catalog:errors.append('event catalog missing:'+event_name)
frame=json.loads((ROOT/'contracts/websocket/frame.schema.json').read_text());refs={x.get('$ref') for x in frame.get('oneOf',[])}
for n in ['hello','welcome','subscribe','subscribed','event','ack','ping','pong','error']:
 if f'#/$defs/{n}' not in refs:errors.append('WebSocket frame missing:'+n)
compose=(ROOT/'compose.yaml').read_text()
for token in ['${POSTGRES_DEV_IMAGE:', '${POSTGRES_TOOLS_IMAGE:', '5432:5432', 'postgresql-init']:
 if token not in compose:errors.append('local PostgreSQL compose control missing:'+token)
tf='\n'.join(p.read_text() for p in (ROOT/'deploy/terraform/aws').glob('*.tf'))
for token in ['engine="postgres"','engine_version=var.postgresql_engine_version','multi_az=true','port=5432','iam_database_authentication_enabled=true']:
 if token.replace(' ','') not in tf.replace(' ',''):errors.append('RDS PostgreSQL control missing:'+token)
relay=(ROOT/'src/backend/edgemint/services/event_relay.py').read_text()
for token in ['@app.websocket("/events/v1"','BROWSER_CLIENT_MUST_USE_BFF','claim_websocket_deliveries','acknowledge_delivery','edgemint.events.v1']:
 if token not in relay:errors.append('Python event relay control missing:'+token)
print(json.dumps({'status':'passed' if not errors else 'failed','transport':'wss','database':'PostgreSQL 18','eventCount':len(asyncapi.get('channels',{})),'errors':errors},indent=2));sys.exit(1 if errors else 0)
