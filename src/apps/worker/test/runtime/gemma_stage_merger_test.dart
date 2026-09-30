import 'package:edgemint_worker/runtime/gemma_generation_output_limit.dart';
import 'package:edgemint_worker/runtime/gemma_stage_merger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const previous = '**۱. آماده‌سازی بستر:**\nبستر را به';
  const next = '**۱. آماده‌سازی بستر:**\nبستر را به آرامی در محفظه بریزید';

  test('repeated heading and incomplete fragment merge into one continuous line', () {
    final merge = GemmaStageMerger.merge(
      previousText: previous,
      nextText: next,
      previousEndedIncomplete: true,
    );

    expect(
      merge.text,
      '**۱. آماده‌سازی بستر:**\nبستر را به آرامی در محفظه بریزید',
    );
    expect(merge.text, isNot(contains('**۱. آماده‌سازی بستر:**\n**۱')));
    expect(merge.duplicateBlocksRemoved, 1);
    expect(merge.overlapRemovedChars, greaterThan(0));
    expect('**۱. آماده‌سازی بستر:**'.allMatches(merge.text), hasLength(1));
  });

  test('partial sentence overlap continues the unfinished clause', () {
    const earlier = 'رطوبت محیط باید کنترل شود زیرا اگر محیط';
    const later = 'اگر محیط بیش از حد مرطوب باشد، خطر قارچ ایجاد می‌شود.';
    final merge = GemmaStageMerger.merge(
      previousText: earlier,
      nextText: later,
      previousEndedIncomplete: true,
    );

    expect(
      merge.text,
      'رطوبت محیط باید کنترل شود زیرا اگر محیط بیش از حد مرطوب باشد، خطر قارچ ایجاد می‌شود.',
    );
    expect(merge.overlapRemovedChars, 'اگر محیط'.length);
    expect(merge.duplicateBlocksRemoved, 0);
  });

  test('duplicate markdown headings are removed before the next paragraph', () {
    final merge = GemmaStageMerger.merge(
      previousText: '## تغذیه\nغذا روزانه داده شود.',
      nextText: '## تغذیه\nآب هم باید تازه باشد.',
      previousEndedIncomplete: false,
    );

    expect(merge.text, '## تغذیه\nغذا روزانه داده شود.\n\nآب هم باید تازه باشد.');
    expect('## تغذیه'.allMatches(merge.text), hasLength(1));
    expect(merge.duplicateBlocksRemoved, 1);
  });

  test('continuation tail keeps only the incomplete ending', () {
    final prefix = 'شروع یکتا ${'الف ' * 400}';
    final soFar = '$prefix\n**۱. آماده‌سازی بستر:**\nبستر را به';
    final tail = GemmaStageMerger.continuationTail(
      soFar,
      endedIncomplete: true,
    );
    final prompt = GemmaStageMerger.continuationPrompt(
      original: 'یک مقاله درباره پرورش مورچه بنویس',
      tail: tail,
    );

    expect(tail.length, lessThanOrEqualTo(GemmaStageMerger.continuationTailMaxChars));
    expect(tail.length, lessThan(500));
    expect(tail, 'بستر را به');
    expect(tail, isNot(contains('شروع یکتا')));
    expect(prompt, contains('دقیقاً از ادامه متن نیمه‌تمام زیر ادامه بده.'));
    expect(prompt, contains('بستر را به'));
    expect(prompt, isNot(contains('شروع یکتا')));
    expect(GemmaStageMerger.overlapWindowChars, 480);
    expect(GemmaStageMerger.continuationTailMaxChars, 400);
  });

  test('staged run passes a short tail and merges the boundary', () async {
    const user = 'یه مقاله در مورد مورچه بده که ۵ صفحه بشه';
    final decision = GemmaGenerationOutputLimit.resolveTextDirect(prompt: user);
    expect(decision.effectiveOutputLimit, 256);
    expect(decision.staged, isTrue);
    final result = await GemmaStagedDirectGeneration.run(
      decision: decision,
      prompt: user,
      generateStage: (stageIndex, stagePrompt) async {
        if (stageIndex == 0) {
          return const GemmaStagePiece(
            text: previous,
            stopReason: GemmaGenerationOutputLimit.outputLimit,
            generatedChunks: 256,
            generatedTokens: 40,
          );
        }
        expect(stagePrompt, contains('بستر را به'));
        expect(stagePrompt, isNot(contains('آماده‌سازی بستر')));
        expect(stagePrompt.length, lessThan(user.length + 500));
        return const GemmaStagePiece(
          text: next,
          stopReason: GemmaGenerationOutputLimit.eos,
          generatedChunks: 30,
          generatedTokens: 20,
        );
      },
    );

    expect(
      result.text,
      '**۱. آماده‌سازی بستر:**\nبستر را به آرامی در محفظه بریزید',
    );
    expect(result.stopReason, GemmaGenerationOutputLimit.eos);
  });
}
