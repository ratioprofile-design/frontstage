import {blockLocked,validateBoard} from './board-operations.js';
const copy=value=>structuredClone(value);
function project(document){return document.project;}
function writable(p,beat){if(!beat||beat.locked||blockLocked(p.frontstageWhiteboard,beat.blockID)||p.beats.find(s=>s.id===beat.sceneID)?.frontstageTextLocked)throw Error('Select an existing unlocked beat and scene.');}
export function pulledOutBeats(document){return (project(document).frontstagePullouts||[]).map(item=>item.beat);}
export function pullOutBeats(document,ids){
 const next=copy(document),p=project(next),b=p.frontstageWhiteboard,selected=b.beats.filter(beat=>ids.has(beat.id));
 if(!ids.size||selected.length!==ids.size)throw Error('Select existing beats.');selected.forEach(beat=>writable(p,beat));
 if(p.frontstagePullouts!=null&&!Array.isArray(p.frontstagePullouts))throw Error('Unsupported archive data is preserved.');
 const archive=p.frontstagePullouts||=[],ordered=[...b.beats].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id));
 for(const beat of selected){if(archive.some(item=>item.id===beat.id))throw Error('Beat already archived.');const index=ordered.indexOf(beat);archive.push({id:beat.id,beat:copy(beat),previousID:ordered[index-1]?.id??null,nextID:ordered[index+1]?.id??null});}
 const links=p.frontstageArchivedDependencies||=[];for(const link of b.dependencies.filter(link=>ids.has(link.cause)||ids.has(link.effect)))if(!links.some(old=>old.id===link.id))links.push(copy(link));
 b.dependencies=b.dependencies.filter(link=>!ids.has(link.cause)&&!ids.has(link.effect));b.beats=b.beats.filter(beat=>!ids.has(beat.id));
 for(const sceneID of new Set(selected.map(beat=>beat.sceneID))){const s=p.beats.find(s=>s.id===sceneID);if(!b.beats.some(beat=>beat.sceneID===sceneID)){s.content='';s.isDisabled=true;}}
 validateBoard(b,new Set(p.beats.map(s=>s.id)));return next;
}
export function restorePulledOutBeats(document,ids,blockID=null){
 const next=copy(document),p=project(next),b=p.frontstageWhiteboard,archive=p.frontstagePullouts||[],selected=archive.filter(item=>ids.has(item.id)).sort((a,b)=>a.beat.order-b.beat.order);
 if(!ids.size||selected.length!==ids.size)throw Error('Select archived beats.');
 for(const item of selected){const beat=copy(item.beat);if(blockID)beat.blockID=blockID;
  if(b.beats.some(old=>old.id===beat.id)||!p.beats.some(s=>s.id===beat.sceneID))throw Error('The original scene is missing or the beat already exists.');
  if(!b.blocks.some(block=>block.id===beat.blockID)||blockLocked(b,beat.blockID))throw Error('Choose an existing unlocked destination container.');
  if(p.beats.find(s=>s.id===beat.sceneID).frontstageTextLocked)throw Error('Unlock the scene before restoring.');
  const ordered=[...b.beats].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id)),after=ordered.findIndex(beat=>beat.id===item.nextID),before=ordered.findIndex(beat=>beat.id===item.previousID);
  beat.order=after>=0?((ordered[after-1]?.order??ordered[after].order-2)+ordered[after].order)/2:before>=0?(ordered[before].order+(ordered[before+1]?.order??ordered[before].order+2))/2:(ordered.at(-1)?.order??-1)+1;
  b.beats.push(beat);
 }
 const links=p.frontstageArchivedDependencies||[],available=new Set(b.beats.map(beat=>beat.id));p.frontstageArchivedDependencies=links.filter(link=>{if(!available.has(link.cause)||!available.has(link.effect))return true;if(!b.dependencies.some(old=>old.id===link.id))b.dependencies.push(copy(link));return false;});
 p.frontstagePullouts=archive.filter(item=>!ids.has(item.id));validateBoard(b,new Set(p.beats.map(s=>s.id)));return next;
}
export function replaceDocument(target,value){for(const key of Object.keys(target))delete target[key];Object.assign(target,value);}

export function validateInclusion(document) {
 const p=project(document),active=new Set((p.frontstageWhiteboard?.beats||[]).map(beat=>beat.id)),archived=new Set();
 if(p.frontstagePullouts==null)return;
 if(!Array.isArray(p.frontstagePullouts))throw Error('Unsupported pulled-out beat archive.');
 for(const entry of p.frontstagePullouts){if(!entry?.id||entry.beat?.id!==entry.id||active.has(entry.id)||archived.has(entry.id))throw Error('A beat cannot be both active and pulled out, or archived twice.');archived.add(entry.id);}
}
