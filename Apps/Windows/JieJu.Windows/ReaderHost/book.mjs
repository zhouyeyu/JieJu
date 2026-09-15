import { postToNative, installCommandListener } from './bridge.mjs';
const themes = {paper:['#fafaf8','#292c29'],night:['#16181d','#e5e7eb'],sepia:['#f4ecd8','#433c30'],sage:['#dde8d5','#293a29']};
const href = document.querySelector('meta[name="jieju-chapter"]')?.content || '';
let restoring = false;
function progress() { return scrollY / Math.max(1, document.documentElement.scrollHeight-innerHeight); }
function locate() { return {kind:'epub',chapterHref:href,textAnchor:JSON.stringify({progress:progress()})}; }
function restore(value) { restoring=true; scrollTo(0,Math.max(0,Math.min(1,value))*Math.max(0,document.documentElement.scrollHeight-innerHeight)); requestAnimationFrame(()=>restoring=false); }
installCommandListener(message => {
  const p=message.payload;
  if(message.type==='configure') {
    const before=progress(), colors=themes[p.theme]||themes.paper;
    for(const [key,value] of Object.entries({'--paper':colors[0],'--ink':colors[1],'--size':`${p.fontSize}px`,'--leading':p.lineHeight,'--margin':`${p.horizontalMargin}px`})) document.documentElement.style.setProperty(key,value);
    document.documentElement.dataset.ruby=String(p.showsFurigana);
    requestAnimationFrame(()=>restore(before));
  }
  if(message.type==='restoreLocation') { try { const anchor=JSON.parse(p.locator.textAnchor||'{}'); requestAnimationFrame(()=>restore(anchor.progress||0)); } catch {} }
  if(message.type==='turnPage') scrollBy({top:p.delta*innerHeight*.85,behavior:'smooth'});
  if(message.type==='clearSelection') getSelection()?.removeAllRanges();
});
let timer;
addEventListener('scroll',()=>{clearTimeout(timer);timer=setTimeout(()=>{if(!restoring)postToNative('locationChanged',{locator:locate()});},200);});
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
postToNative('ready',{readerKind:'epub'});
