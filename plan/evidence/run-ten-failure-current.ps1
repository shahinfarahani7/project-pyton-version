$ErrorActionPreference = "Continue"
$tests = @(
  "test/inference/llm/map_json_repair_acceptance_test.dart",
  "test/inference/llm/phase2_evidence_contract_test.dart",
  "test/inference/llm/phase2_map_prompt_contract_test.dart",
  "test/inference/llm/qwen_map_truncation_policy_test.dart",
  "test/inference/llm/task_f71a56dd_regression_test.dart",
  "test/integration/phase_03_runtime_smoke_test.dart",
  "test/validation/literal_escape_json_recovery_test.dart",
  "test/widget_test.dart"
)
$out = "d:\shakhsi\Edgemint\project-pyton-version\plan\evidence\ten-failure-current-worktree.log"
Remove-Item $out -ErrorAction SilentlyContinue
foreach ($t in $tests) {
  Add-Content $out "`n========== CURRENT flutter test $t ==========`n"
  Push-Location "d:\shakhsi\Edgemint\project-pyton-version\src\apps\worker"
  flutter test $t 2>&1 | Tee-Object -Append -FilePath $out
  $code = $LASTEXITCODE
  Add-Content $out "`nEXIT_CODE=$code`n"
  Pop-Location
}
