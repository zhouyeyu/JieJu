import test from 'node:test';
import assert from 'node:assert/strict';
import { pageCountForExtent, pageForOffset, progressForPage, pageForProgress } from '../Sources/pagination.mjs';

test('computes horizontal EPUB pages from viewport-sized columns', () => {
  assert.equal(pageCountForExtent(3000, 1000), 3);
  assert.equal(pageCountForExtent(999, 1000), 1);
  assert.equal(pageForOffset(1990, 1000, 3), 2);
  assert.equal(pageForOffset(-100, 1000, 3), 0);
});

test('maps pagination progress across reflowed page counts', () => {
  assert.equal(progressForPage(2, 5), 0.5);
  assert.equal(pageForProgress(0.5, 9), 4);
  assert.equal(pageForProgress(2, 9), 8);
  assert.equal(pageForProgress(-1, 9), 0);
});
