import {scriptSegments,board,heading} from './workspace-model.js';
import {applyTypography} from './script-typography.js';
import {groupDualParagraphs} from './dual-dialogue.js';
import {decorateDialogue} from './dialogue-rules.js';
import {sceneChanged} from './production-revision.js';
import {paginateParagraphs} from './pagination.js';

export function timelinePageWeights(beatIDs,spans){
 if(!beatIDs.length||new Set(beatIDs).size!==beatIDs.length)return null;
 let previous=-1;for(const id of beatIDs){const span=spans[id];if(!span||![span.start,span.end].every(Number.isFinite)||span.start<0||span.end<=span.start||span.start<=previous)return null;previous=span.start;}
 const result={};for(const[id,index]of beatIDs.map((id,index)=>[id,index])){const start=index?spans[id].start:0,end=index+1<beatIDs.length?spans[beatIDs[index+1]].start:spans[id].end;if(end<=start)return null;result[id]=end-start;}return result;
}

// Reuse Pages' font/style rules, dual columns and actual paginator in an isolated hidden surface.
// No selection, live editor nodes or persisted document content are touched.
export function measureTimelinePages(doc,{paper='a4',cleanHTML,ownerDocument=document}={}){
 const segments=scriptSegments(doc);if(!segments.length||segments.some(s=>!s.beatIDs.length))return null;
 const byID=new Map(board(doc).beats.map(b=>[b.id,b])),ids=segments.flatMap(s=>s.beatIDs),desk=ownerDocument.createElement('div');desk.className='pages-desk timeline-page-measurement';desk.setAttribute('aria-hidden','true');desk.inert=true;Object.assign(desk.style,{position:'fixed',left:'-100000px',top:'0',width:'1000px',visibility:'hidden',pointerEvents:'none',height:'auto',minHeight:'0',overflow:'visible'});ownerDocument.body.append(desk);
 try{
  const width=paper==='a4'?595.2756:612,height=(paper==='a4'?841.8898:792)-144,pages=[];
  const node=(tag,text,cls)=>{const n=ownerDocument.createElement(tag);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n;};
  const makePage=()=>{const page=node('article',null,'paper-sheet');page.style.width=width+'px';page.style.height=height+144+'px';applyTypography(page,doc.project.frontstageScriptLayout);const content=node('div',null,'page-content script-text');page.append(content);desk.append(page);pages.push(content);return content;};
  const entries=[];
  for(const segment of segments){
   const title=node('p',`${segment.number}  ${heading(segment.scene)}${segment.continuation?' (CONTINUED)':''}`,'sc-line sc-slugline');title.dataset.timingBeat=segment.beatIDs[0];if(sceneChanged(doc,segment.scene.id))title.dataset.revised='true';entries.push({node:title,newPage:segment.scene.frontstagePageStart&&!segment.continuation});
   const source=node('div');source.innerHTML=cleanHTML(segment.html);
   const ranges=[];let cursor=0,combined='';for(const id of segment.beatIDs){const part=node('div');part.innerHTML=cleanHTML(byID.get(id)?.html??'');const text=part.textContent;ranges.push({id,start:cursor,end:cursor+text.length});cursor+=text.length;combined+=text;}
   if(combined!==source.textContent)return null;
   cursor=0;for(let paragraph of [...source.childNodes]){if(paragraph.nodeType!==1){const p=node('p',paragraph.textContent);paragraph.replaceWith(p);paragraph=p;}const length=paragraph.textContent.length,owner=ranges.find(r=>cursor>=r.start&&cursor<r.end)||ranges.find(r=>cursor===r.start);if(!owner||cursor+length>owner.end)return null;paragraph.dataset.timingBeat=owner.id;cursor+=length;}
   decorateDialogue(source);
   for(const paragraph of groupDualParagraphs([...source.children]))entries.push({node:paragraph});
  }
  paginateParagraphs(makePage,entries,height);
  const spans={};for(const[pageIndex,content]of pages.entries()){const frame=content.getBoundingClientRect();for(const paragraph of content.querySelectorAll('[data-timing-beat]')){const r=paragraph.getBoundingClientRect();if(r.height<=0||r.bottom>frame.top+height+2)return null;const id=paragraph.dataset.timingBeat,start=pageIndex+Math.max(0,(r.top-frame.top)/height),end=pageIndex+Math.min(1,(r.bottom-frame.top)/height);if(!spans[id])spans[id]={start,end};else{spans[id].start=Math.min(spans[id].start,start);spans[id].end=Math.max(spans[id].end,end);}}}
  return timelinePageWeights(ids,spans);
 }finally{desk.remove();}
}
