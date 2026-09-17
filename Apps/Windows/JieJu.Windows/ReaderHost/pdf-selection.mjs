export function cleanPdfText(value) {
  return String(value ?? "").replace(/[\u00ad\u200b\ufeff]/g, "").replace(/[ \t\r\n]+/g, " ").trim();
}

export function pdfSelectionContext(pageText, selectedText) {
  const text = cleanPdfText(pageText), targetText = cleanPdfText(selectedText);
  if (!targetText) return { targetText: "", containingSentence: "", precedingContext: null, followingContext: null, textOffset: null };
  const offset = text.indexOf(targetText);
  const sentences = [...text.matchAll(/[^.!?。！？\n]+[.!?。！？]?/g)]
    .map(match => ({ text: cleanPdfText(match[0]), start: match.index ?? 0 }))
    .filter(item => item.text);
  const selected = offset >= 0 ? sentences.findIndex(item => offset >= item.start && offset < item.start + item.text.length) : -1;
  return {
    targetText,
    containingSentence: selected >= 0 ? sentences[selected].text : targetText,
    precedingContext: selected > 0 ? sentences[selected - 1].text : null,
    followingContext: selected >= 0 && selected + 1 < sentences.length ? sentences[selected + 1].text : null,
    textOffset: offset >= 0 ? offset : null
  };
}
