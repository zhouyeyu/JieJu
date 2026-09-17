import test from 'node:test';
import assert from 'node:assert/strict';
import { resolvePdfOutline, outlineIndexForPage } from '../../../Apps/Windows/JieJu.Windows/ReaderHost/pdf-outline.mjs';

test('resolves nested PDF outline destinations to zero-based pages', async () => {
  const pdf = { getDestination:async name => name === 'chapter2' ? [{ num:9 }] : null, getPageIndex:async ref => ref.num };
  const entries = await resolvePdfOutline(pdf, [
    { title:'第一卷', dest:[{ num:0 }], items:[{ title:'第一章', dest:[{ num:1 }] }] },
    { title:'第二章', dest:'chapter2' }
  ]);
  assert.deepEqual(entries, [
    { title:'第一卷', pageIndex:0, level:0 },
    { title:'第一章', pageIndex:1, level:1 },
    { title:'第二章', pageIndex:9, level:0 }
  ]);
});

test('chooses the latest PDF outline entry at the current page', () => {
  const entries = [{ pageIndex:0 }, { pageIndex:12 }, { pageIndex:59 }];
  assert.equal(outlineIndexForPage(entries, 11), 0);
  assert.equal(outlineIndexForPage(entries, 12), 1);
  assert.equal(outlineIndexForPage(entries, 94), 2);
});
