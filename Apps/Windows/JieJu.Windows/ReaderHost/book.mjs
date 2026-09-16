import { postToNative, installCommandListener } from './bridge.mjs';
import { pageCountForExtent, pageForOffset, progressForPage, pageForProgress } from './pagination.mjs';

const themes = {paper:['#fafaf8','#292c29'],night:['#16181d','#e5e7eb'],sepia:['#f4ecd8','#433c30'],sage:['#dde8d5','#293a29']};
const href = document.querySelector('meta[name="jieju-chapter"]')?.content || '';
let page = 0, pageCount = 1, layoutTimer, restoring = false, pendingProgress = 0;

function viewportWidth() { return Math.max(1, document.documentElement.clientWidth || innerWidth); }
function measurePageCount() { return pageCountForExtent(Math.max(document.body.scrollWidth, document.documentElement.scrollWidth), viewportWidth()); }
function progress() { return progressForPage(page, pageCount); }
function locate() { return {kind:'epub',chapterHref:href,textAnchor:JSON.stringify({progress:progress(),page,pageCount})}; }
function publish(isReflowing = false, saveLocation = true) {
  window.__jiejuPaginationState = {page,pageCount,progress:progress(),isReflowing};
  postToNative('paginationChanged',{pageIndex:page,pageCount,progression:progress(),isReflowing,locator:locate()});
  if (saveLocation && !isReflowing) postToNative('locationChanged',{locator:locate()});
}
function setPage(value, saveLocation = true) {
  page = Math.max(0,Math.min(pageCount-1,Number(value)||0));
  restoring = true;
  scrollTo({left:page*viewportWidth(),top:0,behavior:'auto'});
  requestAnimationFrame(()=>restoring=false);
  publish(false,saveLocation);
}
function layout() {
  clearTimeout(layoutTimer);
  publish(true,false);
  requestAnimationFrame(()=>requestAnimationFrame(()=>{
    pageCount=measurePageCount();
    setPage(pageForProgress(pendingProgress,pageCount),false);
    publish(false,true);
  }));
}
function scheduleLayout(value = progress()) {
  pendingProgress=Math.max(0,Math.min(1,Number(value)||0));
  clearTimeout(layoutTimer); layoutTimer=setTimeout(layout,80);
}
function turnPage(delta) {
  getSelection()?.removeAllRanges();
  setPage(page+Math.sign(Number(delta)||0));
}

installCommandListener(message => {
  const p=message.payload;
  if(message.type==='configure') {
    const before=progress(), colors=themes[p.theme]||themes.paper;
    for(const [key,value] of Object.entries({'--paper':colors[0],'--ink':colors[1],'--size':`${p.fontSize}px`,'--leading':p.lineHeight,'--margin':`${p.horizontalMargin}px`})) document.documentElement.style.setProperty(key,value);
    document.documentElement.dataset.ruby=String(p.showsFurigana);
    scheduleLayout(before);
  }
  if(message.type==='restoreLocation') {
    try { const anchor=JSON.parse(p.locator.textAnchor||'{}'); scheduleLayout(anchor.progress||0); } catch { scheduleLayout(0); }
  }
  if(message.type==='turnPage') turnPage(p.delta);
  if(message.type==='clearSelection') getSelection()?.removeAllRanges();
});

addEventListener('resize',()=>scheduleLayout(progress()));
addEventListener('scroll',()=>{
  if(restoring)return;
  clearTimeout(layoutTimer); layoutTimer=setTimeout(()=>{
    const next=pageForOffset(scrollX,viewportWidth(),pageCount);
    if(next!==page){page=next;publish();}
  },120);
});
addEventListener('keydown',event=>{
  if(event.defaultPrevented||event.ctrlKey||event.metaKey||event.altKey||event.target?.closest?.('input,textarea,select,button,[contenteditable="true"]'))return;
  if(event.key==='ArrowLeft'||event.key==='PageUp'){event.preventDefault();turnPage(-1);}
  if(event.key==='ArrowRight'||event.key==='PageDown'||event.key===' '){event.preventDefault();turnPage(1);}
});
document.addEventListener('click',e=>{if(e.target.closest('a'))e.preventDefault();});

function plainText(node) {
  const copy=node.cloneContents ? node.cloneContents() : node.cloneNode(true);
  copy.querySelectorAll?.('rt,rp,script,style').forEach(item=>item.remove());
  return (copy.textContent||'').replace(/\s+/g,' ').trim();
}
function selectionContext(target, surrounding) {
  const parts=surrounding.match(/[^.!?。！？]+[.!?。！？]?/g)?.map(x=>x.trim()).filter(Boolean)||[];
  const index=parts.findIndex(x=>x.includes(target));
  return { containingSentence:index>=0?parts[index]:target, precedingContext:index>0?parts[index-1]:null, followingContext:index>=0&&index+1<parts.length?parts[index+1]:null };
}
let selectionTimer;
function reportSelection() {
  clearTimeout(selectionTimer); selectionTimer=setTimeout(()=>{
    const selection=getSelection();
    if(!selection||selection.isCollapsed||selection.rangeCount===0) { postToNative('selectionChanged',{targetText:''}); return; }
    const range=selection.getRangeAt(0), targetText=plainText(range), surrounding=plainText(document.body);
    if(!targetText) { postToNative('selectionChanged',{targetText:''}); return; }
    postToNative('selectionChanged',{targetText,...selectionContext(targetText,surrounding),locator:locate()});
  },120);
}
document.addEventListener('selectionchange',reportSelection);
scheduleLayout(0);
postToNative('ready',{readerKind:'epub'});
