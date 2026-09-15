import { getDocument, GlobalWorkerOptions } from './vendor/pdfjs/build/pdf.mjs';
import { EventBus, PDFLinkService, PDFViewer } from './vendor/pdfjs/web/pdf_viewer.mjs';
import { postToNative, installCommandListener } from './bridge.mjs';
import { cleanPdfText, pdfSelectionContext } from './pdf-selection.mjs';
import { resolvePdfOutline, outlineIndexForPage } from './pdf-outline.mjs';
import { buildVerticalTextModel, verticalWordAt } from './pdf-vertical-selection.mjs';

GlobalWorkerOptions.workerSrc = './vendor/pdfjs/build/pdf.worker.min.mjs';
const eventBus = new EventBus();
const linkService = new PDFLinkService({ eventBus });
const maxCanvasPixels = 2 ** 25;
const viewer = new PDFViewer({ container:document.querySelector('#viewerContainer'), viewer:document.querySelector('#viewer'), eventBus, linkService, textLayerMode:1, maxCanvasPixels, maxCanvasDim:32767, capCanvasAreaFactor:-1, enableDetailCanvas:true });
linkService.setViewer(viewer);
const pageNumber = document.querySelector('#pageNumber'), pageCount = document.querySelector('#pageCount'), outline = document.querySelector('#outline'), zoomValue = document.querySelector('#zoomValue'), selectionHint = document.querySelector('#selectionHint'), message = document.querySelector('#message');
let documentProxy, selectionTimer, outlineEntries = [], suppressNativeSelectionUntil = 0;
const pageTexts = new Map();
const verticalModels = new Map();

function setPage(value) { if (documentProxy) viewer.currentPageNumber = Math.max(1, Math.min(documentProxy.numPages, Number(value) || 1)); }
document.querySelector('#previous').addEventListener('click', () => setPage(viewer.currentPageNumber - 1));
document.querySelector('#next').addEventListener('click', () => setPage(viewer.currentPageNumber + 1));
document.querySelector('#zoomOut').addEventListener('click', () => viewer.decreaseScale());
document.querySelector('#zoomIn').addEventListener('click', () => viewer.increaseScale());
document.querySelector('#fit').addEventListener('click', () => viewer.currentScaleValue = 'page-width');
pageNumber.addEventListener('change', () => setPage(pageNumber.value));
outline.addEventListener('change', () => { const entry = outlineEntries[Number(outline.value)]; if (entry) setPage(entry.pageIndex + 1); });

eventBus.on('pagesinit', () => { viewer.currentScaleValue = 'page-width'; });
eventBus.on('scalechanging', event => { zoomValue.textContent = `${Math.round(event.scale * 100)}%`; });
eventBus.on('pagechanging', event => {
  pageNumber.value = String(event.pageNumber);
  const outlineIndex = outlineIndexForPage(outlineEntries, event.pageNumber - 1);
  outline.value = outlineIndex >= 0 ? String(outlineIndex) : '';
  selectionHint.hidden = !verticalModels.has(event.pageNumber);
  postToNative('locationChanged', { locator:{ kind:'pdf', pageIndex:event.pageNumber - 1 }, chapterTitle:outlineIndex >= 0 ? outlineEntries[outlineIndex].title : null });
});
eventBus.on('pagerendered', async event => {
  if (!pageTexts.has(event.pageNumber)) {
    const page = await documentProxy.getPage(event.pageNumber), content = await page.getTextContent();
    pageTexts.set(event.pageNumber, cleanPdfText(content.items.map(item => item.str + (item.hasEOL ? '\n' : ' ')).join('')));
  }
});
eventBus.on('textlayerrendered', event => {
  const pageElement = document.querySelector(`.page[data-page-number="${event.pageNumber}"]`);
  const spans = [...(pageElement?.querySelectorAll('.textLayer span') ?? [])];
  const records = spans.map((element, sourceIndex) => {
    const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
    return { text:element.textContent, centerX:rect.left + rect.width / 2, top:rect.top, fontSize:parseFloat(style.fontSize), element, sourceIndex };
  });
  const model = buildVerticalTextModel(records);
  if (model) {
    verticalModels.set(event.pageNumber, model);
    pageTexts.set(event.pageNumber, cleanPdfText(model.pageText));
  } else verticalModels.delete(event.pageNumber);
  if (event.pageNumber === viewer.currentPageNumber) selectionHint.hidden = !model;
});

async function sha256(value) {
  const bytes = new TextEncoder().encode(value), digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
}
document.addEventListener('selectionchange', () => {
  if (Date.now() < suppressNativeSelectionUntil) return;
  clearTimeout(selectionTimer);
  selectionTimer = setTimeout(async () => {
    const selection = getSelection();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) { postToNative('selectionChanged', { targetText:'' }); return; }
    const range = selection.getRangeAt(0), pageElement = range.commonAncestorContainer.nodeType === Node.ELEMENT_NODE ? range.commonAncestorContainer.closest?.('.page') : range.commonAncestorContainer.parentElement?.closest('.page');
    const selectedText = cleanPdfText(selection.toString());
    if (!pageElement || !selectedText) return;
    const page = Number(pageElement.dataset.pageNumber), context = pdfSelectionContext(pageTexts.get(page) ?? pageElement.textContent, selectedText);
    postToNative('selectionChanged', { ...context, locator:{ kind:'pdf', pageIndex:page - 1, textOffset:context.textOffset, textHash:await sha256(context.targetText) } });
  }, 120);
});

function clearAssistedSelection() { document.querySelectorAll('.jieju-assisted-selection').forEach(element => element.classList.remove('jieju-assisted-selection')); }

async function postAssistedSelection(page, result) {
  clearTimeout(selectionTimer);
  suppressNativeSelectionUntil = Date.now() + 300;
  getSelection()?.removeAllRanges();
  clearAssistedSelection();
  result.records.forEach(record => record.element?.classList.add('jieju-assisted-selection'));
  const context = pdfSelectionContext(pageTexts.get(page) ?? '', result.targetText);
  postToNative('selectionChanged', { ...context, selectionMethod:'vertical-assisted', locator:{ kind:'pdf', pageIndex:page - 1, textOffset:context.textOffset, textHash:await sha256(context.targetText) } });
}

document.querySelector('#viewerContainer').addEventListener('click', event => {
  const span = event.target.closest?.('.textLayer span'), pageElement = span?.closest('.page');
  if (!span || !pageElement || !getSelection()?.isCollapsed) return;
  const page = Number(pageElement.dataset.pageNumber), model = verticalModels.get(page);
  if (!model) return;
  const spans = [...pageElement.querySelectorAll('.textLayer span')], result = verticalWordAt(model, spans.indexOf(span));
  if (result) void postAssistedSelection(page, result);
});

installCommandListener(command => {
  if (command.type === 'restoreLocation') setPage((command.payload.locator?.pageIndex ?? 0) + 1);
  if (command.type === 'turnPage') setPage(viewer.currentPageNumber + Math.sign(command.payload.delta));
  if (command.type === 'clearSelection') { getSelection()?.removeAllRanges(); clearAssistedSelection(); }
});

try {
  const task = getDocument({ url:'https://document.jieju.invalid/current.pdf', cMapUrl:'./vendor/pdfjs/cmaps/', cMapPacked:true, standardFontDataUrl:'./vendor/pdfjs/standard_fonts/', disableRange:true, disableStream:true, enableHWA:true });
  documentProxy = await task.promise;
  outlineEntries = await resolvePdfOutline(documentProxy, await documentProxy.getOutline());
  outline.replaceChildren();
  if (outlineEntries.length) outlineEntries.forEach((entry, index) => outline.add(new Option(`${'　'.repeat(entry.level)}${entry.title} · ${entry.pageIndex + 1}`, String(index))));
  else { outline.add(new Option('无目录', '')); outline.disabled = true; }
  pageCount.textContent = String(documentProxy.numPages);
  pageNumber.max = String(documentProxy.numPages);
  linkService.setDocument(documentProxy);
  viewer.setDocument(documentProxy);
  message.textContent = `${documentProxy.numPages} 页 · 可选择文字`;
  postToNative('ready', { readerKind:'pdf', pageCount:documentProxy.numPages, outlineCount:outlineEntries.length });
} catch (error) {
  message.textContent = 'PDF 载入失败';
  postToNative('error', { message:String(error?.message ?? error) });
}

window.__jiejuSmokeSelect = async (page = 1) => {
  setPage(page);
  let spans = [];
  for (let attempt = 0; attempt < 40; attempt++) {
    setPage(page);
    const model = verticalModels.get(page);
    if (model) {
      const candidate = model.columns.flatMap(column => column.records).find(record => verticalWordAt(model, record.sourceIndex)?.targetText.length > 1);
      if (candidate) { await postAssistedSelection(page, verticalWordAt(model, candidate.sourceIndex)); return true; }
    }
    spans = [...document.querySelectorAll(`.page[data-page-number="${page}"] .textLayer span`)];
    if (spans.some(item => item.textContent?.trim())) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  const span = spans.find(item => item.textContent?.trim().length > 0);
  if (!span) return false;
  const range = document.createRange(); range.selectNodeContents(span);
  const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
  document.dispatchEvent(new Event('selectionchange'));
  return true;
};

window.__jiejuSmokeVerticalSelectResult = null;
window.__jiejuSmokeVerticalSelect = async (page = 1) => {
  window.__jiejuSmokeVerticalSelectResult = null;
  setPage(page);
  for (let attempt = 0; attempt < 60; attempt++) {
    setPage(page);
    const model = verticalModels.get(page);
    if (model) {
      const candidate = model.columns.flatMap(column => column.records).find(record => verticalWordAt(model, record.sourceIndex)?.targetText.length > 1);
      if (candidate) {
        const result = verticalWordAt(model, candidate.sourceIndex);
        await postAssistedSelection(page, result);
        window.__jiejuSmokeVerticalSelectResult = { targetText:result.targetText, highlighted:result.records.length, pageText:pageTexts.get(page) };
        return;
      }
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  window.__jiejuSmokeVerticalSelectResult = false;
};

window.__jiejuSmokeZoomResult = null;
window.__jiejuSmokeZoom = async (page = 1) => {
  window.__jiejuSmokeZoomResult = null;
  setPage(page); viewer.currentScale = 4;
  for (let attempt = 0; attempt < 60; attempt++) {
    setPage(page);
    const canvas = document.querySelector(`.page[data-page-number="${page}"] canvas`);
    if (canvas?.clientWidth > 0 && canvas?.clientHeight > 0) {
      const pixelRatio = Math.min(devicePixelRatio || 1, 1);
      if (canvas.width >= canvas.clientWidth * pixelRatio * .98 && canvas.height >= canvas.clientHeight * pixelRatio * .98) {
        window.__jiejuSmokeZoomResult = true; return;
      }
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  window.__jiejuSmokeZoomResult = false;
};
