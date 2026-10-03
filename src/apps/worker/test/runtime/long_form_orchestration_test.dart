import 'package:edgemint_worker/inference/llm/qwen_task_processor.dart';
import 'package:edgemint_worker/contracts/worker_task_request.dart';
import 'package:edgemint_worker/contracts/worker_task_result.dart';
import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/runtime/gemma_stage_merger.dart';
import 'package:edgemint_worker/runtime/long_form_section_plan.dart';
import 'package:edgemint_worker/tasks/handlers/direct_prompt_handler.dart';
import 'package:edgemint_worker/telemetry/worker_task_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const prompt = 'یک مقاله جامع در مورد مورچه بده';

  test('A: intro stage completes مقدمه and moves current to تعریف و دامنه', () {
    final progress = LongFormSectionProgress(LongFormSectionPlan.sectionsFor(prompt));
    progress.observe(
      'مقدمه\n'
      'مورچه‌ها حشرات اجتماعی هستند.\n'
      '\n'
      'تعریف و دامنه\n'
      'مورچه از خانواده Formicidae است.',
    );
    expect(progress.completedSections, ['مقدمه']);
    expect(progress.currentSection, 'تعریف و دامنه');
    expect(progress.remainingSections.first, 'ساختار');
    expect(progress.remainingSections, isNot(contains('مقدمه')));
    expect(progress.remainingSections, isNot(contains('تعریف و دامنه')));
  });

  test('B: definition stage completes تعریف و دامنه and moves current to ساختار', () {
    final progress = LongFormSectionProgress(LongFormSectionPlan.sectionsFor(prompt));
    progress.observe('مقدمه\nشروع.\n\nتعریف و دامنه\nدامنه.');
    progress.observe(
      'تعریف و دامنه\n'
      'ادامه دامنه.\n'
      '\n'
      'ساختار\n'
      'بدن سه بخش دارد.',
    );
    expect(progress.completedSections, ['مقدمه', 'تعریف و دامنه']);
    expect(progress.currentSection, 'ساختار');
    expect(progress.remainingSections.first, 'فرایند');
  });

  test('C: markdown and bold headings are the same section', () {
    const plain = 'ساختار';
    final variants = ['**ساختار**', '### ساختار', '## ساختار', 'ساختار'];
    final canonical = LongFormSectionPlan.normalizeHeading(plain);
    for (final variant in variants) {
      expect(LongFormSectionPlan.normalizeHeading(variant), canonical);
    }

    final progress = LongFormSectionProgress(LongFormSectionPlan.sectionsFor(prompt));
    progress.observe('**مقدمه**\nشروع.');
    progress.observe('### تعریف و دامنه\nدامنه.');
    progress.observe('## ساختار\nبدن.');
    expect(progress.completedSections, ['مقدمه', 'تعریف و دامنه']);
    expect(progress.currentSection, 'ساختار');
  });

  test('section cursor does not move backward', () {
    final progress = LongFormSectionProgress(LongFormSectionPlan.sectionsFor(prompt));
    progress.observe('مقدمه\nشروع.\n\nتعریف و دامنه\nدامنه.\n\nساختار\nبدن.');
    expect(progress.currentSection, 'ساختار');
    progress.observe('مقدمه\nاین بخش قبلاً تمام شده است.');
    expect(progress.currentSection, 'ساختار');
    expect(progress.completedSections, ['مقدمه', 'تعریف و دامنه']);
  });

  test('a finished sentence without a section heading does not advance', () {
    final progress = LongFormSectionProgress(LongFormSectionPlan.sectionsFor(prompt));
    progress.observe('مقدمه تمام شد.');
    expect(progress.currentSection, 'مقدمه');
    expect(progress.completedSections, isEmpty);
  });

  test('D: a completed section is not appended again', () {
    final merge = GemmaStageMerger.merge(
      previousText: 'مقدمه\nمورچه‌ها اجتماعی هستند.\n\nتعریف و دامنه\nدامنه کلونی است.',
      nextText: '### تعریف و دامنه\n'
          'این متن تکراری است.\n'
          '\n'
          'ساختار\n'
          'بدن سه بخش دارد.\n'
          '\n'
          '**تعریف و دامنه**\n'
          'باز هم تکرار.',
      previousEndedIncomplete: false,
      completedSectionTitles: const ['مقدمه', 'تعریف و دامنه'],
      plannedSectionTitles: LongFormSectionPlan.persianSections,
    );
    expect(merge.text, isNot(contains('این متن تکراری است')));
    expect(merge.text, isNot(contains('باز هم تکرار')));
    expect(merge.text, contains('ساختار'));
    expect(merge.text, contains('بدن سه بخش دارد.'));
    expect(merge.duplicateBlocksRemoved, greaterThan(0));
    expect(
      merge.text.split('\n').where((line) => line.trim() == 'تعریف و دامنه'),
      hasLength(1),
    );
    expect(merge.text, isNot(contains('### تعریف و دامنه')));
    expect(merge.text, isNot(contains('**تعریف و دامنه**')));
  });

  test('E: orchestration instructions do not enter the final output', () async {
    final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: prompt);
    final staged = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: prompt,
      hardMaxStages: 2,
      generateStage: (stageIndex, stagePrompt) async {
        if (stageIndex == 0) {
          return const GemmaStagePiece(
            text: 'مقدمه\nمورچه‌ها اجتماعی هستند.\n\nتعریف و دامنه\nدامنه کلونی است.',
            stopReason: GemmaGenerationOutputLimit.outputLimit,
            generatedChunks: 40,
            generatedTokens: 20,
          );
        }
        return const GemmaStagePiece(
          text: 'درخواست:\n'
              'یک مقاله جامع در مورد مورچه بده\n'
              '\n'
              'ادامهٔ متن:\n'
              'دامنه کلونی است.\n'
              '\n'
              'Completed sections:\n'
              '- مقدمه\n'
              '\n'
              'Current section:\n'
              '- مقدمه\n'
              '\n'
              'Remaining sections:\n'
              '- تعریف و دامنه\n'
              '\n'
              'Continue only from the current unfinished point.\n'
              'Do not repeat completed sections.\n'
              'When and only when the entire requested document is truly complete, append exactly:\n'
              '<EDGEMINT_DONE>\n'
              '\n'
              'ساختار\n'
              'بدن سه بخش دارد.',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          generatedChunks: 40,
          generatedTokens: 20,
        );
      },
    );
    expect(staged.text, isNot(contains('درخواست:')));
    expect(staged.text, isNot(contains('ادامهٔ متن:')));
    expect(staged.text, isNot(contains('Completed sections:')));
    expect(staged.text, isNot(contains('Current section:')));
    expect(staged.text, isNot(contains('Remaining sections:')));
    expect(staged.text, isNot(contains('Continue only')));
    expect(staged.text, isNot(contains('When and only when')));
    expect(staged.text, isNot(contains('<EDGEMINT_DONE>')));
    expect(staged.text, isNot(contains('یک مقاله جامع در مورد مورچه بده')));
    expect(staged.text, contains('مورچه‌ها اجتماعی هستند.'));
    expect(staged.text, contains('بدن سه بخش دارد.'));
  });

  test('F: hard stage limit still truncates without completing the document', () async {
    const user = 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه';
    final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: user);
    var calls = 0;
    final staged = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: user,
      generateStage: (stageIndex, stagePrompt) async {
        calls += 1;
        return GemmaStagePiece(
          text: 'بخش $stageIndex تمام شد.',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          generatedChunks: 256,
          generatedTokens: 40,
        );
      },
    );
    expect(calls, GemmaGenerationOutputLimit.longFormHardMaxStages);
    expect(staged.complete, isFalse);
    expect(staged.truncated, isTrue);
    expect(staged.stopReason, GemmaGenerationOutputLimit.longFormStageLimit);
    final result = DirectPromptHandler.resultFor(
      request: WorkerTaskRequest(
        schemaVersion: '1.0',
        taskId: 'tsk-ant',
        idempotencyKey: 'idem-ant',
        type: 'text.direct.v1',
        input: const WorkerTaskInput(text: user),
        options: const WorkerTaskOptions(allowTruncatedOutput: true),
      ),
      generation: DirectGenerationReceipt(
        text: staged.text,
        stopReason: staged.stopReason,
        configuredOutputLimit: 256,
        generatedChunks: staged.generatedChunks,
        generatedTokens: staged.generatedTokens,
      ),
      metrics: WorkerTaskMetrics(),
    );
    expect(result.status, WorkerResultStatus.succeededWithTruncation);
    expect(result.toJson()['status'], 'SUCCEEDED_WITH_TRUNCATION');
  });

  test('acceptance: ant article progresses and does not repeat leaked sections', () async {
    final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: prompt);
    final prompts = <String>[];
    const laterSections = <String>[
      'فرایند',
      'سازوکار',
      'زمینه و محیط',
      'اثرها و رابطه‌ها',
      'پیامدهای عملی',
      'تنوع‌ها',
    ];
    final staged = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: prompt,
      generateStage: (stageIndex, stagePrompt) async {
        prompts.add(stagePrompt);
        if (stageIndex == 0) {
          return const GemmaStagePiece(
            text: 'مقدمه\n'
                'مورچه‌ها حشرات اجتماعی هستند.\n'
                '\n'
                'تعریف و دامنه\n'
                'مورچه از خانواده Formicidae است.',
            stopReason: GemmaGenerationOutputLimit.outputLimit,
            generatedChunks: 80,
            generatedTokens: 40,
          );
        }
        if (stageIndex == 1) {
          expect(stagePrompt, contains('دقیقاً از ادامه متن نیمه‌تمام زیر ادامه بده.'));
          expect(stagePrompt, contains('Current section:\n- تعریف و دامنه'));
          return const GemmaStagePiece(
            text: 'درخواست:\n'
                'یک مقاله جامع در مورد مورچه بده\n'
                '\n'
                'ادامهٔ متن:\n'
                'مورچه از خانواده Formicidae است.\n'
                '\n'
                'تعریف و دامنه\n'
                'دامنه شامل همه گونه‌های مورچه است.\n'
                '\n'
                'ساختار\n'
                'بدن مورچه سه بخش اصلی دارد.\n'
                '\n'
                'تعریف و دامنه\n'
                'تعریف دوباره آمده است.\n'
                '\n'
                'ساختار\n'
                'ساختار دوباره آمده است.',
            stopReason: GemmaGenerationOutputLimit.outputLimit,
            generatedChunks: 80,
            generatedTokens: 40,
          );
        }
        final section = laterSections[stageIndex - 2];
        return GemmaStagePiece(
          text: '$section\nجمله یکتای $section بدون پایان سند.',
          stopReason: GemmaGenerationOutputLimit.outputLimit,
          generatedChunks: 40,
          generatedTokens: 20,
        );
      },
    );

    expect(prompts[0], contains('Current section:\n- مقدمه'));
    expect(prompts[0], contains('Remaining sections:\n- تعریف و دامنه'));
    expect(prompts[1], contains('Completed sections:\n- مقدمه'));
    expect(prompts[1], contains('Current section:\n- تعریف و دامنه'));
    expect(prompts[1], isNot(contains('Current section:\n- مقدمه')));
    expect(prompts[1], contains('Remaining sections:\n- ساختار'));
    expect(prompts[2], contains('Completed sections:\n- مقدمه\n- تعریف و دامنه'));
    expect(prompts[2], contains('Current section:\n- ساختار'));
    expect(prompts[2], contains('Remaining sections:\n- فرایند'));
    expect(prompts[2], isNot(contains('Current section:\n- مقدمه')));

    expect(staged.complete, isFalse);
    expect(staged.truncated, isTrue);
    expect(staged.stopReason, GemmaGenerationOutputLimit.longFormStageLimit);
    expect(staged.stagesUsed, 8);
    expect(staged.text, contains('مورچه‌ها حشرات اجتماعی هستند.'));
    expect(staged.text, contains('دامنه شامل همه گونه‌های مورچه است.'));
    expect(staged.text, contains('بدن مورچه سه بخش اصلی دارد.'));
    expect(staged.text, contains('جمله یکتای تنوع‌ها بدون پایان سند.'));
    expect(staged.text, isNot(contains('درخواست:')));
    expect(staged.text, isNot(contains('ادامهٔ متن:')));
    expect(staged.text, isNot(contains('یک مقاله جامع در مورد مورچه بده')));
    expect(staged.text, isNot(contains('تعریف دوباره آمده است')));
    expect(staged.text, isNot(contains('ساختار دوباره آمده است')));
    expect(
      staged.text.split('\n').where((line) => line.trim() == 'تعریف و دامنه'),
      hasLength(1),
    );
    expect(
      staged.text.split('\n').where((line) => line.trim() == 'ساختار'),
      hasLength(1),
    );

    final result = DirectPromptHandler.resultFor(
      request: WorkerTaskRequest(
        schemaVersion: '1.0',
        taskId: 'tsk-ant-article',
        idempotencyKey: 'idem-ant-article',
        type: 'text.direct.v1',
        input: const WorkerTaskInput(text: prompt),
        options: const WorkerTaskOptions(allowTruncatedOutput: true),
      ),
      generation: DirectGenerationReceipt(
        text: staged.text,
        stopReason: staged.stopReason,
        configuredOutputLimit: 256,
        generatedChunks: staged.generatedChunks,
        generatedTokens: staged.generatedTokens,
      ),
      metrics: WorkerTaskMetrics(),
    );
    expect(result.toJson()['status'], 'SUCCEEDED_WITH_TRUNCATION');
  });
}
