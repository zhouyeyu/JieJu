import test from 'node:test';
import assert from 'node:assert/strict';
import { buildVerticalTextModel, verticalWordAt } from '../../../Apps/Windows/JieJu.Windows/ReaderHost/pdf-vertical-selection.mjs';

function glyph(text, centerX, top, fontSize = 15) { return { text, centerX, top, fontSize }; }

test('reconstructs vertical Japanese right-to-left and removes smaller ruby', () => {
  const records = [
    ...[...'財前助教授。'].map((text, index) => glyph(text, 200, index * 16)),
    glyph('ざい', 208, 0, 7.5), glyph('ぜん', 208, 16, 7.5),
    ...[...'里見脩二は。'].map((text, index) => glyph(text, 180, index * 16)),
    glyph('しゅうじ', 188, 32, 7.5)
  ];
  const model = buildVerticalTextModel(records);
  assert.ok(model);
  assert.equal(model.pageText, '財前助教授。\n里見脩二は。');
  assert.doesNotMatch(model.pageText, /ざい|ぜん|しゅうじ/);
});

test('selects the Japanese word containing the clicked main glyph', () => {
  const records = [
    ...[...'彼は助教授です。'].map((text, index) => glyph(text, 200, index * 16)),
    ...[...'別の縦書き列。'].map((text, index) => glyph(text, 180, index * 16))
  ];
  const model = buildVerticalTextModel(records);
  const selection = verticalWordAt(model, 2);
  assert.ok(selection);
  assert.equal(selection.targetText, '助教授');
  assert.equal(selection.records.length, 3);
});

test('does not classify an ordinary horizontal line as vertical text', () => {
  const records = [...'This is a horizontal PDF line.'].map((text, index) => glyph(text, index * 12, 20));
  assert.equal(buildVerticalTextModel(records), null);
});
