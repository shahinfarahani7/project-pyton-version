#!/usr/bin/env python3
from pathlib import Path
import json,re,sys,yaml
ROOT=Path(__file__).resolve().parents[1];errors=[];tf='\n'.join(p.read_text() for p in (ROOT/'deploy/terraform/aws').glob('*.tf'))
for required in ['aws_eks_cluster','aws_eks_node_group','aws_db_instance','aws_wafv2_web_acl','aws_backup_plan','aws_cloudtrail','aws_iam_openid_connect_provider']:
 if f'resource "{required}"' not in tf:errors.append('missing terraform resource '+required)
for required in ['engine="postgres"','postgres18','18.4','5432','iam_database_authentication_enabled=true','rds.force_ssl']:
 if required.replace(' ','') not in tf.replace(' ',''):errors.append('PostgreSQL infrastructure source missing '+required)
vals=yaml.safe_load((ROOT/'deploy/helm/edgemint/values-ci.yaml').read_text())
for name,svc in vals['services'].items():
 if not re.fullmatch(r'sha256:[a-f0-9]{64}',svc['image']['digest']):errors.append('invalid CI digest '+name)
 if not vals['irsaRoles'].get(name):errors.append('missing CI IRSA '+name)
if 'event-relay' not in vals['services']:errors.append('event relay missing from Helm')
if errors:print('\n'.join(errors));sys.exit(1)
print(json.dumps({'status':'passed','services':len(vals['services']),'database':'PostgreSQL 18','transport':'WebSocket'},indent=2))
