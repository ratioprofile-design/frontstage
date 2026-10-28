import {label,breakdownEntries} from './workspace-model.js';
export const highlightColors={Yellow:'#fff0a6',Green:'#bde9bf',Blue:'#b9dcff',Pink:'#f7c3dd',Orange:'#ffd2a1',Purple:'#d9c5f7'};
export const categoryColors=Object.fromEntries(['CAST','EXTRAS','STUNTS','VEHICLES','PROPS','SFX','WARDROBE','MAKEUP','ANIMALS','SOUND','SET_DRESSING','GREENERY','SPECIAL_EQUIPMENT','LIGHTING_GRIP','SAFETY'].map((c,i)=>[c,Object.values(highlightColors)[i%6]]));
const validID=value=>/^[A-Za-z0-9_-]{1,120}$/.test(value||'');
export function requirementCatalog(document){const map=new Map();for(const scene of document.project.beats)for(const entry of breakdownEntries(scene))if(entry.id)map.set(String(entry.id),{...entry,sceneID:scene.id});return map;}
export function refreshAnnotationPresentation(root,document){const catalog=requirementCatalog(document);for(const node of root.querySelectorAll('[data-dot-breakdown]')){const entry=catalog.get(node.dataset.dotBreakdown);node.classList.toggle('dot-source-missing',!entry);node.style.setProperty('--dot-tag-color',categoryColors[entry?.category||entry?.bucket]||'#dddddd');node.title=entry?`${label(entry.category||entry.bucket)}: ${entry.name}`:'Breakdown item no longer exists';}for(const node of root.querySelectorAll('[data-dot-highlight]'))node.style.setProperty('--dot-highlight-color',highlightColors[node.dataset.dotHighlight]||'transparent');}
export function annotationIDs(html){return [...html.matchAll(/\bdata-dot-breakdown\s*=\s*["']([A-Za-z0-9_-]{1,120})["']/g)].map(m=>m[1]);}
export function remapAnnotationIDs(html,ids){return html.replace(/(\bdata-dot-breakdown\s*=\s*["'])([A-Za-z0-9_-]{1,120})(["'])/g,(all,a,id,b)=>a+(ids.get(id)||id)+b);}
// Only edit metadata and ownership. Source text and unknown requirement fields stay intact.
export function reconcileScriptAnnotations(document){
 const p=document.project,beats=[...(p.frontstageWhiteboard?.beats||[]),...(p.frontstagePullouts||[]).map(e=>e.beat)],owners=new Map();
 if(![...beats.map(b=>b.html||''),...p.beats.flatMap(s=>[s.content||'',s.frontstageHeadingMarkup||''])].some(html=>html.includes('data-dot-')))return;
 const catalog=requirementCatalog(document);
 for(const scene of p.beats)for(const id of annotationIDs(scene.frontstageHeadingMarkup||'')){if(!owners.has(id))owners.set(id,new Set());owners.get(id).add(scene.id);}
 for(const beat of beats)for(const id of annotationIDs(beat.html||'')){if(!owners.has(id))owners.set(id,new Set());owners.get(id).add(beat.sceneID);}
 for(const beat of beats){const remap=new Map();for(const id of new Set(annotationIDs(beat.html||''))){const entry=catalog.get(id);if(!entry||entry.sceneID===beat.sceneID)continue;const destination=p.beats.find(s=>s.id===beat.sceneID);if(!destination||destination.frontstageTextLocked)continue;
   const source=p.beats.find(s=>s.id===entry.sceneID),list=source?.[entry.storage]?.[entry.bucket],raw=list?.find(r=>r?.id===id);if(!raw)continue;
   const existing=breakdownEntries(destination).find(r=>r.frontstageSourceID===id);let newID=existing?.id;
   if(!newID){const copy=structuredClone(raw),move=!owners.get(id)?.has(entry.sceneID)&&!source.frontstageTextLocked;newID=move?id:crypto.randomUUID();copy.id=newID;if(!move)copy.frontstageSourceID=id;(destination[entry.storage]||={})[entry.bucket]||=[];destination[entry.storage][entry.bucket].push(copy);if(move)list.splice(list.indexOf(raw),1);catalog.set(newID,{...entry,id:newID,sceneID:destination.id});}remap.set(id,newID);
  }beat.html=remapAnnotationIDs(beat.html||'',remap);}
 const current=requirementCatalog(document);const clean=html=>html.replace(/<span\b[^>]*>/gi,tag=>{const m=tag.match(/data-dot-breakdown\s*=\s*["']([^"']+)["']/i);if(!m)return tag;const entry=current.get(m[1]);tag=tag.replace(/\sdata-dot-category\s*=\s*["'][^"']*["']/gi,'');if(!entry)return tag.replace(/\sdata-dot-breakdown\s*=\s*["'][^"']*["']/gi,'');const category=entry.category||entry.bucket;return tag.slice(0,-1)+` data-dot-category="${validID(category)?category:'IMPORTED'}">`;});
 for(const beat of beats)beat.html=clean(beat.html||'');for(const scene of p.beats){scene.content=clean(scene.content||'');if(scene.frontstageHeadingMarkup)scene.frontstageHeadingMarkup=clean(scene.frontstageHeadingMarkup);}
}
export function applyInlineAnnotation(root,range,attributes){
 const nodes=[],walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);while(walker.nextNode())if(range.intersectsNode(walker.currentNode))nodes.push(walker.currentNode);
 for(const node of nodes.reverse()){let start=node===range.startContainer?range.startOffset:0,end=node===range.endContainer?range.endOffset:node.length;if(end<=start)continue;const selected=node.splitText(start);selected.splitText(end-start);const span=document.createElement('span');for(const[key,value]of Object.entries(attributes))span.setAttribute(key,value);selected.replaceWith(span);span.append(selected);}
}
function rewriteSelectedRuns(root,range,removeAttribute,clearStyle=false){
 const nodes=[],walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);while(walker.nextNode())if(range.intersectsNode(walker.currentNode))nodes.push(walker.currentNode);
 for(const node of nodes.reverse()){
  const start=node===range.startContainer?range.startOffset:0,end=node===range.endContainer?range.endOffset:node.length;if(end<=start)continue;
  const selected=node.splitText(start);selected.splitText(end-start);let block=selected.parentElement;while(block!==root&&block.parentElement!==root)block=block.parentElement;
  const chain=[];for(let ancestor=selected.parentElement;ancestor&&ancestor!==block;ancestor=ancestor.parentElement)chain.push(ancestor);const top=chain.at(-1);if(!top)continue;
  let middle=document.createTextNode(selected.data);
  for(const ancestor of chain){if(clearStyle&&['B','STRONG','I','EM','U','S','STRIKE','FONT'].includes(ancestor.tagName))continue;const copy=ancestor.cloneNode(false);if(clearStyle)copy.removeAttribute('style');if(removeAttribute){copy.removeAttribute(removeAttribute);if(removeAttribute==='data-dot-breakdown'){copy.removeAttribute('data-dot-category');copy.removeAttribute('title');}}copy.append(middle);middle=copy;}
  const before=top.cloneNode(false),after=top.cloneNode(false),r=document.createRange();r.selectNodeContents(top);r.setEndBefore(selected);before.append(r.extractContents());r.selectNodeContents(top);r.setStartAfter(selected);after.append(r.extractContents());const replacements=[];if(before.textContent)replacements.push(before);replacements.push(middle);if(after.textContent)replacements.push(after);top.replaceWith(...replacements);
 }
}
export function removeInlineAnnotation(root,range,attribute){rewriteSelectedRuns(root,range,attribute);}
export function clearInlineFormatting(root,range){rewriteSelectedRuns(root,range,null,true);}
