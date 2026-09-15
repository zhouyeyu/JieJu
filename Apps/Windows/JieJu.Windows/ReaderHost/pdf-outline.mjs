export async function resolvePdfOutline(pdf, outline) {
  const entries = [];
  async function visit(items, level) {
    for (const item of items ?? []) {
      let destination = item.dest;
      if (typeof destination === 'string') destination = await pdf.getDestination(destination);
      if (Array.isArray(destination) && destination[0]) {
        try {
          const pageIndex = Number.isInteger(destination[0]) ? destination[0] : await pdf.getPageIndex(destination[0]);
          entries.push({ title:String(item.title ?? '').trim() || `第 ${pageIndex + 1} 页`, pageIndex, level });
        } catch {}
      }
      await visit(item.items, level + 1);
    }
  }
  await visit(outline, 0);
  return entries;
}

export function outlineIndexForPage(entries, pageIndex) {
  let selected = -1;
  for (let index = 0; index < entries.length; index++) {
    if (entries[index].pageIndex > pageIndex) break;
    selected = index;
  }
  return selected;
}
