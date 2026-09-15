import { getDocument, GlobalWorkerOptions } from './vendor/pdfjs/build/pdf.mjs';
import { EventBus, PDFLinkService, PDFViewer } from './vendor/pdfjs/web/pdf_viewer.mjs';
import { postToNative, installCommandListener } from './bridge.mjs';
import { cleanPdfText, pdfSelectionContext } from './pdf-selection.mjs';

GlobalWorkerOptions.workerSrc = './vendor/pdfjs/build/pdf.worker.min.mjs';
const eventBus = new EventBus();
const linkService = new PDFLinkService({ eventBus });
const viewer = new PDFViewer({ container:document.querySelector('#viewerContainer'), viewer:document.querySelector('#viewer'), eventBus, linkService, textLayerMode:1 });
linkService.setViewer(viewer);
const pageNumber = document.querySelector('#pageNumber'), pageCount = document.querySelector('#pageCount'), message = document.querySelector('#message');
let documentProxy, selectionTimer;
const pageTexts = new Map();

function setPage(value) { if (documentProxy) viewer.currentPageNumber = Math.max(1, Math.min(documentProxy.numPages, Number(value) || 1)); }
document.querySelector('#previous').addEventListener('click', () => setPage(viewer.currentPageNumber - 1));
document.querySelector('#next').addEventListener('click', () => setPage(viewer.currentPageNumber + 1));
document.querySelector('#zoomOut').addEventListener('click', () => viewer.decreaseScale());
document.querySelector('#zoomIn').addEventListener('click', () => viewer.increaseScale());
document.querySelector('#fit').addEventListener('click', () => viewer.currentScaleValue = 'page-width');
pageNumber.addEventListener('change', () => setPage(pageNumber.value));

eventBus.on('pagesinit', () => { viewer.currentScaleValue = 'page-width'; });
eventBus.on('pagechanging', event => {
  pageNumber.value = String(event.pageNumber);
  postToNative('locationChanged', { locator:{ kind:'pdf', pageIndex:event.pageNumber - 1 } });
});
eventBus.on('pagerendered', async event => {
  if (!pageTexts.has(event.pageNumber)) {
    const page = await documentProxy.getPage(event.pageNumber), content = await page.getTextContent();
    pageTexts.set(event.pageNumber, cleanPdfText(content.items.map(item => item.str + (item.hasEOL ? '\n' : ' ')).join('')));
  }
});

async function sha256(value) {
  const bytes = new TextEncoder().encode(value), digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map(value => value.toString(16).padStart(2, '0')).join('');
}
document.addEventListener('selectionchange', () => {
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

installCommandListener(command => {
  if (command.type === 'restoreLocation') setPage((command.payload.locator?.pageIndex ?? 0) + 1);
  if (command.type === 'turnPage') setPage(viewer.currentPageNumber + Math.sign(command.payload.delta));
  if (command.type === 'clearSelection') getSelection()?.removeAllRanges();
});

try {
  const task = getDocument({ url:'https://document.jieju.invalid/current.pdf', cMapUrl:'./vendor/pdfjs/cmaps/', cMapPacked:true, standardFontDataUrl:'./vendor/pdfjs/standard_fonts/', disableRange:true, disableStream:true });
  documentProxy = await task.promise;
  pageCount.textContent = String(documentProxy.numPages);
  pageNumber.max = String(documentProxy.numPages);
  linkService.setDocument(documentProxy);
  viewer.setDocument(documentProxy);
  message.textContent = `${documentProxy.numPages} 页 · 可选择文字`;
  postToNative('ready', { readerKind:'pdf', pageCount:documentProxy.numPages });
} catch (error) {
  message.textContent = 'PDF 载入失败';
  postToNative('error', { message:String(error?.message ?? error) });
}

window.__jiejuSmokeSelect = async (page = 1) => {
  setPage(page);
  let spans = [];
  for (let attempt = 0; attempt < 40; attempt++) {
    setPage(page);
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
