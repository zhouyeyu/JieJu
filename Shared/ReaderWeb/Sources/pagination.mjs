export function pageCountForExtent(extent, viewportWidth) {
  const width = Math.max(1, Number(viewportWidth) || 1);
  return Math.max(1, Math.ceil((Math.max(0, Number(extent) || 0) - 1) / width));
}

export function pageForOffset(offset, viewportWidth, pageCount) {
  const width = Math.max(1, Number(viewportWidth) || 1);
  return Math.max(0, Math.min(Math.max(1, pageCount) - 1, Math.round((Number(offset) || 0) / width)));
}

export function progressForPage(page, pageCount) {
  const count = Math.max(1, Number(pageCount) || 1);
  return count <= 1 ? 0 : Math.max(0, Math.min(1, (Number(page) || 0) / (count - 1)));
}

export function pageForProgress(progress, pageCount) {
  const count = Math.max(1, Number(pageCount) || 1);
  const value = Math.max(0, Math.min(1, Number(progress) || 0));
  return Math.max(0, Math.min(count - 1, Math.round(value * (count - 1))));
}
