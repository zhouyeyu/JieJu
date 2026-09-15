import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanPdfText, pdfSelectionContext } from '../../../Apps/Windows/JieJu.Windows/ReaderHost/pdf-selection.mjs';

test('cleans PDF line wrapping without changing selected words', () => {
  assert.equal(cleanPdfText('  彼女は\n 学校で\u200b本を読む。  '), '彼女は 学校で本を読む。');
});

test('extracts the containing sentence and adjacent PDF context', () => {
  const result = pdfSelectionContext('前の文です。彼女は本を読んでいます。次の文です。', '本を読んでいます');
  assert.equal(result.containingSentence, '彼女は本を読んでいます。');
  assert.equal(result.precedingContext, '前の文です。');
  assert.equal(result.followingContext, '次の文です。');
  assert.equal(result.textOffset, 9);
});

test('keeps a valid PDF selection when page extraction order differs', () => {
  const result = pdfSelectionContext('抽出順が異なる本文', '画面で選んだ文字');
  assert.equal(result.targetText, '画面で選んだ文字');
  assert.equal(result.containingSentence, '画面で選んだ文字');
  assert.equal(result.textOffset, null);
});
