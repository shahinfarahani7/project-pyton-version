#!/usr/bin/env python3
from pathlib import Path
import json,re,sys,yaml
try:
    import hcl2
except ImportError:
    hcl2=None
ROOT=Path(__file__).resolve().parents[1]
errors=[]; warnings=[]
tf_files=sorted((ROOT/'deploy/terraform/aws').glob('*.tf'))

def basic_hcl_sanity(text: str, name: str) -> None:
    """Conservative fallback: validate balanced delimiters; semantic controls are checked below."""
    for opening,closing,label in [("{","}","braces"),("[","]","brackets"),("(",")","parentheses")]:
        if text.count(opening)!=text.count(closing):
            errors.append(f"{name}: unbalanced {label}")

if hcl2 is None:
    warnings.append('python-hcl2 unavailable; Terraform received structural source validation only. Install tools/requirements.lock for full HCL parsing.')
    for p in tf_files: basic_hcl_sanity(p.read_text(),str(p.relative_to(ROOT)))
else:
    for p in tf_files:
        try:
            with p.open() as f:hcl2.load(f)
        except Exception as e:errors.append(f'{p.relative_to(ROOT)}: invalid HCL: {e}')
tf='\n'.join(p.read_text() for p in tf_files)
for r in ['aws_vpc','aws_eks_cluster','aws_eks_node_group','aws_iam_openid_connect_provider','aws_db_instance','aws_s3_bucket','aws_ecr_repository','aws_cognito_user_pool','aws_wafv2_web_acl','aws_backup_plan','aws_cloudtrail','aws_budgets_budget']:
    if f'resource "{r}"' not in tf:errors.append('missing Terraform resource '+r)
for pattern,label in [(r'engine\s*=\s*"postgres"','engine'),(r'port\s*=\s*5432','port'),(r'multi_az\s*=\s*true','multi_az'),(r'storage_encrypted\s*=\s*true','encryption'),(r'deletion_protection\s*=\s*var\.deletion_protection','deletion protection'),(r'iam_database_authentication_enabled\s*=\s*true','IAM auth'),(r'lifecycle\s*\{[\s\S]*?prevent_destroy\s*=\s*true','prevent destroy')]:
    if not re.search(pattern,tf):errors.append('database Terraform control missing:'+label)
ci=yaml.safe_load((ROOT/'deploy/helm/edgemint/values-ci.yaml').read_text());services=ci.get('services',{})
if len(services)!=21:errors.append(f'Helm service count must be 21, got {len(services)}')
for name,svc in services.items():
    if not re.fullmatch(r'sha256:[a-f0-9]{64}',svc.get('image',{}).get('digest','')):errors.append(name+':invalid digest')
    if not re.fullmatch(r'arn:aws:iam::[0-9]{12}:role/.+',ci.get('irsaRoles',{}).get(name,'')):errors.append(name+':invalid IRSA')
controls='\n'.join(p.read_text() for p in (ROOT/'deploy/helm/edgemint/templates').glob('*.yaml'))
for token in ['runAsNonRoot: true','readOnlyRootFilesystem: true','allowPrivilegeEscalation: false','topologySpreadConstraints','startupProbe','readinessProbe','livenessProbe','NetworkPolicy','ExternalSecret','wafv2-acl-arn','/events/v1']:
    if token not in controls:errors.append('Helm control missing:'+token)
status='failed' if errors else ('passed_with_warning' if warnings else 'passed')
print(json.dumps({'status':status,'terraformFiles':len(tf_files),'helmServices':len(services),'hclParser':'python-hcl2' if hcl2 else 'structural-fallback','warnings':warnings,'errors':errors},indent=2));sys.exit(1 if errors else 0)
