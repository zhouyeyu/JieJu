const visibleText = value => String(value ?? '').replace(/[\u0000\u00ad\u200b\ufeff]/g, '').trim();

function median(values) {
  const sorted = [...values].sort((left, right) => left - right);
  if (!sorted.length) return 0;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function groupColumns(records, tolerance) {
  const columns = [];
  for (const record of [...records].sort((left, right) => right.centerX - left.centerX)) {
    let column = columns.find(candidate => Math.abs(candidate.centerX - record.centerX) <= tolerance);
    if (!column) {
      column = { centerX:record.centerX, records:[] };
      columns.push(column);
    }
    column.records.push(record);
    column.centerX = column.records.reduce((sum, item) => sum + item.centerX, 0) / column.records.length;
  }
  return columns.sort((left, right) => right.centerX - left.centerX);
}

export function buildVerticalTextModel(inputRecords) {
  const candidates = inputRecords
    .map((record, sourceIndex) => ({ ...record, sourceIndex, text:visibleText(record.text) }))
    .filter(record => record.text && Number.isFinite(record.fontSize) && record.fontSize > 0 && Number.isFinite(record.centerX) && Number.isFinite(record.top));
  if (candidates.length < 12) return null;

  const sizeBuckets = new Map();
  for (const record of candidates) {
    const bucket = Math.round(record.fontSize * 2) / 2;
    sizeBuckets.set(bucket, (sizeBuckets.get(bucket) ?? 0) + [...record.text].length);
  }
  const dominantSize = [...sizeBuckets].sort((left, right) => right[1] - left[1] || right[0] - left[0])[0]?.[0] ?? median(candidates.map(item => item.fontSize));
  const mainRecords = candidates.filter(record => record.fontSize >= dominantSize * .76 && record.fontSize <= dominantSize * 1.35);
  const columns = groupColumns(mainRecords, dominantSize * .42)
    .map(column => ({ ...column, records:column.records.sort((left, right) => left.top - right.top) }))
    .filter(column => column.records.length >= 2);
  const longColumns = columns.filter(column => column.records.length >= 5);
  const verticalRecordCount = longColumns.reduce((sum, column) => sum + column.records.length, 0);
  if (longColumns.length < 2 || verticalRecordCount < Math.max(10, mainRecords.length * .35)) return null;

  let pageOffset = 0;
  const modelColumns = columns.map(column => {
    const records = column.records.map(record => {
      const start = pageOffset;
      pageOffset += record.text.length;
      return { ...record, start, end:pageOffset };
    });
    pageOffset += 1;
    return { ...column, records, text:records.map(record => record.text).join('') };
  });
  return {
    dominantSize,
    columns:modelColumns,
    pageText:modelColumns.map(column => column.text).join('\n')
  };
}

export function verticalWordAt(model, sourceIndex, locale = 'ja') {
  if (!model) return null;
  const column = model.columns.find(candidate => candidate.records.some(record => record.sourceIndex === sourceIndex));
  if (!column) return null;
  const clicked = column.records.find(record => record.sourceIndex === sourceIndex);
  const columnOffset = column.records.filter(record => record.start < clicked.start).reduce((sum, record) => sum + record.text.length, 0);
  let start = columnOffset, end = columnOffset + clicked.text.length;
  if (globalThis.Intl?.Segmenter) {
    const segments = [...new Intl.Segmenter(locale, { granularity:'word' }).segment(column.text)];
    const match = segments.find(segment => columnOffset >= segment.index && columnOffset < segment.index + segment.segment.length);
    if (match?.isWordLike) { start = match.index; end = match.index + match.segment.length; }
  }
  let cursor = 0;
  const records = column.records.filter(record => {
    const recordStart = cursor, recordEnd = cursor + record.text.length;
    cursor = recordEnd;
    return recordStart < end && recordEnd > start;
  });
  const targetText = column.text.slice(start, end);
  return targetText ? { targetText, records } : null;
}
