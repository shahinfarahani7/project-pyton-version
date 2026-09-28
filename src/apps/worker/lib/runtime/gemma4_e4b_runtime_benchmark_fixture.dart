import '../models/worker_model_catalog.dart';

/// Deterministic benchmark payload (no private/customer data).
abstract final class Gemma4E4bRuntimeBenchmarkFixture {
  static const benchmarkContextTokens = WorkerModelCatalog.benchmarkContextTokens;
  static const benchmarkMaxOutputTokens =
      WorkerModelCatalog.benchmarkMaxOutputTokens;

  /// Fixed system instruction for structured JSON output.
  static const systemInstruction = '''
You are a structured analysis assistant. Respond with JSON only, no markdown fences.
Schema: {"summary": string, "keyPoints": string[], "riskLevel": "low"|"medium"|"high"}
''';

  /// ~1200–1400 token class synthetic logistics brief (deterministic).
  static const userPrompt = '''
Analyze the following operational report and produce the JSON schema requested.

Report ID: BENCH-GEMMA4-E4B-2026-09-28
Region: EU-NORTH-3
Facility: EdgeMint consolidation hub 17
Window: 2026-09-01T00:00:00Z through 2026-09-27T23:59:59Z

Throughput summary:
- Inbound pallets processed: 18420
- Outbound shipments: 17602
- Average dwell time hours: 14.6
- Peak queue depth: 312 units
- SLA breaches: 41 (0.23% of shipments)
- Rework events: 128
- Temperature excursions (cold chain): 3 minor, 0 major
- Scanner misreads corrected manually: 902
- Automated sortation accuracy: 99.41%
- Labor overtime hours: 2260
- Temporary staff utilization: 18.4%

Incident log excerpts:
1) Conveyor belt CB-4 intermittent jam on 2026-09-07; cleared in 22 minutes; root cause: misaligned guide roller.
2) WMS sync lag peaked at 9 minutes on 2026-09-12 during catalog refresh; no data loss confirmed.
3) Forklift FL-19 battery degradation triggered swap policy update on 2026-09-15.
4) Dock door D-12 weather seal tear caused humidity spike in staging lane B; humidity returned to baseline within 45 minutes.
5) Label printer LP-7 ribbon failure caused 120 label reprints; no mislabeled outbound cartons detected in audit sample n=500.

Quality audits:
- Random weight verification sample: 1200 cartons, 2 out-of-tolerance (0.17%)
- Barcode spot check: 800 labels, 1 unreadable at 30cm (replaced)
- Security seal inspection: 400 trailers, 0 failures

Customer impact:
- Tier-1 customer tickets opened: 12
- Tier-1 customer tickets closed within 24h: 11
- Credits issued EUR: 4200
- Net promoter survey responses: 88, average 4.2/5

Energy and sustainability:
- kWh per 1000 shipments: 118.4 (target 120.0)
- Recycled dunnage percentage: 62%
- Water usage cubic meters: 910

Staffing notes:
- Training completion for new hires: 96%
- Safety near-miss reports: 7, all reviewed
- Ergonomic assessments completed: 34/34 scheduled

Forecast implications for next 30 days:
- Expected inbound growth: 4.8%
- Carrier capacity constraint on lane HEL->ARN
- Recommended overtime cap: 12% above baseline
- Recommended spare parts stock increase: guide rollers (+15%), printer ribbons (+20%)

Provide summary, 4-6 keyPoints, and riskLevel based on SLA breaches, cold chain, and customer tickets.
''';

  static const benchmarkTaskType = 'text.direct';
}
