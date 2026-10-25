// Portable browser operations mirror the native document rules. Return copies so failures are atomic.
const copy = value => structuredClone(value);
export function validateBoard(board, sceneIDs) {
  const fail = () => { throw Error('The whiteboard contains invalid identifiers, geometry or references.'); };
  const coordinate = n => Number.isFinite(n) && Math.abs(n) <= 1000000;
  const unique = rows => Array.isArray(rows) && rows.every(r => r && typeof r.id === 'string' && r.id) && new Set(rows.map(r => r.id)).size === rows.length;
  const strings = rows => Array.isArray(rows) && rows.every(s => typeof s === 'string');
  if (board?.version !== 1 || !['layers', 'blocks', 'beats', 'dependencies', 'strokes'].every(k => unique(board[k])) || !board.layers.length || !coordinate(board.viewport?.origin?.x) || !coordinate(board.viewport?.origin?.y) || !Number.isFinite(board.viewport?.zoom) || board.viewport.zoom < .15 || board.viewport.zoom > 3) fail();
  const layers = new Set(board.layers.map(l => l.id)), blocks = new Map(board.blocks.map(b => [b.id, b])), beats = new Set(board.beats.map(b => b.id));
  for (const layer of board.layers) if ((layer.useBlocks!=null&&typeof layer.useBlocks!=='boolean') || typeof layer.name !== 'string' || !Number.isFinite(layer.height) || layer.height < 100 || layer.height > 10000 || !['locked', 'collapsed', 'unused'].every(k => typeof layer[k] === 'boolean')) fail();
  for (const block of board.blocks) {
    const policy=board.layers.find(l=>l.id===block.layerID)?.useBlocks,isBlock=!block.standalone&&block.containerKind!=='beatGroup';
    if(policy===false&&isBlock)throw Error('Enable Use Blocks on the layer before creating a block.');
    if(policy===true&&!isBlock){let parent=blocks.get(block.parentID),contained=false,seen=new Set();while(parent&&!seen.has(parent.id)){seen.add(parent.id);if(parent.layerID!==block.layerID)break;if(!parent.standalone&&parent.containerKind!=='beatGroup'){contained=true;break;}parent=blocks.get(parent.parentID);}if(!contained)throw Error('This layer uses blocks. Place beats and groups inside a block.');}
    if (!layers.has(block.layerID) || typeof block.name !== 'string' || !coordinate(block.position?.x) || !coordinate(block.position?.y) || !Number.isFinite(block.width) || block.width < 140 || block.width > 2000 || !['locked', 'collapsed'].every(k => typeof block[k] === 'boolean') || (block.parentID != null && !blocks.has(block.parentID))) fail();
    const seen = new Set([block.id]);
    for (let parent = block.parentID; parent != null; parent = blocks.get(parent)?.parentID) { if (seen.has(parent)) fail(); seen.add(parent); }
  }
  for(const b of board.beats){
    if(b.timelineDuration!=null&&(!Number.isFinite(b.timelineDuration)||b.timelineDuration<=0||b.timelineDuration>1000))fail();
    for(const [key,max]of [['emotionChanges',100],['tensions',5]])if(b[key]!=null&&(typeof b[key]!=='object'||Array.isArray(b[key])||Object.values(b[key]).some(v=>!Number.isFinite(v)||Math.abs(v)>max)))fail();
    if(b.emotionAbsoluteTags!=null&&!strings(b.emotionAbsoluteTags))fail();
  }
  for (const beat of board.beats) if ((beat.position != null && (!coordinate(beat.position.x)||!coordinate(beat.position.y)||beat.position.x<0||beat.position.y<24)) || !sceneIDs.has(beat.sceneID) || !blocks.has(beat.blockID) || !coordinate(beat.order) || !coordinate(beat.start) || beat.start < 0 || !Number.isFinite(beat.duration) || beat.duration < .05 || beat.duration > 1000 || !['title', 'synopsis', 'html', 'color'].every(k => typeof beat[k] === 'string') || !['story', 'subtext'].includes(beat.kind) || !strings(beat.characters) || !strings(beat.tags) || !['mustBeCaused', 'omitted', 'locked'].every(k => typeof beat[k] === 'boolean')) fail();
  for (const edge of board.dependencies) if (!beats.has(edge.cause) || !beats.has(edge.effect) || edge.cause === edge.effect || typeof edge.reference !== 'boolean' || typeof edge.reason !== 'string') fail();
  for (const stroke of board.strokes) if (!Array.isArray(stroke.points) || stroke.points.length > 10000 || !stroke.points.every(p => coordinate(p?.x) && coordinate(p?.y)) || !Number.isFinite(stroke.width) || stroke.width < .5 || stroke.width > 30 || typeof stroke.color !== 'string') fail();
  return board;
}
export function lockedBlockIDs(board) {
  const layers = new Set(board.layers.filter(l => l.locked).map(l => l.id)), children = new Map();
  for (const block of board.blocks) if (block.parentID) { if (!children.has(block.parentID)) children.set(block.parentID, []); children.get(block.parentID).push(block.id); }
  const locked = new Set(board.blocks.filter(b => b.locked || layers.has(b.layerID)).map(b => b.id)), queue = [...locked];
  for (let i = 0; i < queue.length; i++) for (const child of children.get(queue[i]) || []) if (!locked.has(child)) { locked.add(child); queue.push(child); }
  return locked;
}
export function blockLocked(board, id) {
  const blocks = new Map(board.blocks.map(b => [b.id, b])), layers = new Map(board.layers.map(l => [l.id, l]));
  const seen = new Set();
  for (let block = blocks.get(id); block && !seen.has(block.id); block = blocks.get(block.parentID)) {
    if (block.locked || layers.get(block.layerID)?.locked) return true;
    seen.add(block.id);
  }
  return false;
}
export function causalOrder(board) {
  const incoming = new Map(board.beats.map(b => [b.id, 0])), outgoing = new Map();
  for (const edge of board.dependencies.filter(e => !e.reference)) {
    if (!incoming.has(edge.cause) || !incoming.has(edge.effect)) throw Error('A dependency refers to a missing beat.');
    incoming.set(edge.effect, incoming.get(edge.effect) + 1);
    if (!outgoing.has(edge.cause)) outgoing.set(edge.cause, []);
    outgoing.get(edge.cause).push(edge.effect);
  }
  const ordered = [...board.beats].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
  const ready = ordered.filter(b => !incoming.get(b.id)).map(b => b.id), result = [];
  for (let i = 0; i < ready.length; i++) {
    const id = ready[i]; result.push(id);
    for (const next of outgoing.get(id) || []) { incoming.set(next, incoming.get(next) - 1); if (!incoming.get(next)) ready.push(next); }
  }
  if (result.length !== board.beats.length) throw Error('A dependency would create a causal loop.');
  return result;
}
export function compactCausalTime(source) {
  const board = copy(source), byID = new Map(board.beats.map(b => [b.id, b])), locked = lockedBlockIDs(board);
  const unusedLayers = new Set(board.layers.filter(l => l.unused).map(l => l.id));
  const unused = new Set(board.blocks.filter(b => unusedLayers.has(b.layerID)).map(b => b.id));
  const incoming = new Map();
  for (const edge of board.dependencies.filter(e => !e.reference)) { if (!incoming.has(edge.effect)) incoming.set(edge.effect, []); incoming.get(edge.effect).push(edge.cause); }
  for (const id of causalOrder(board)) {
    const beat = byID.get(id); if (beat.omitted || unused.has(beat.blockID)) continue;
    const earliest = Math.max(0, ...(incoming.get(id) || []).map(id => byID.get(id)).filter(b => !b.omitted && !unused.has(b.blockID)).map(b => b.start + b.duration));
    if (beat.locked || locked.has(beat.blockID)) { if (beat.start < earliest) throw Error(`${beat.title} is locked and blocks compaction.`); }
    else beat.start = earliest;
  }
  return board;
}
export function descendantBlocks(board, ids) {
  const result = new Set(ids); let changed = true;
  while (changed) { const count = result.size; for (const block of board.blocks) if (result.has(block.parentID)) result.add(block.id); changed = count !== result.size; }
  return result;
}
export function moveBlocks(source, ids, dx, dy, {layerID, ripple=false}={}) {
  const board = copy(source), moving = descendantBlocks(board, ids), items = board.blocks.filter(b => moving.has(b.id)), locked = lockedBlockIDs(board);
  if (!ids.size || !Number.isFinite(dx) || !Number.isFinite(dy) || items.length !== moving.size || items.some(b => locked.has(b.id))) throw Error('Select unlocked blocks to move.');
  if(layerID && !board.layers.some(l=>l.id===layerID&&!l.locked))throw Error('Unlock the destination lane.');
  dx = Math.max(dx, -Math.min(...items.map(b => b.position.x))); dy = Math.max(dy, 32 - Math.min(...items.map(b => b.position.y)));
  for (const block of items) {
    block.position.x += dx; block.position.y += dy;
    if(layerID){if(block.layerID!==layerID && !moving.has(block.parentID))delete block.parentID;block.layerID=layerID;}
    if (Math.abs(block.position.x) > 1000000 || Math.abs(block.position.y) > 1000000) throw Error('Board position is out of range.');
  }
  if(ripple){
    const before=new Map(board.beats.map(b=>[b.id,b.start]));
    for(const beat of board.beats)if(moving.has(beat.blockID))beat.start=Math.max(0,beat.start+dx/120);
    const requested=new Map(board.beats.map(b=>[b.id,b.start]));
    const resolved=resolveCausalTime(board),pushes=new Map();
    for(const beat of resolved.beats){const baseline=moving.has(beat.blockID)?requested.get(beat.id):before.get(beat.id);pushes.set(beat.blockID,Math.max(pushes.get(beat.blockID)||0,beat.start-baseline));}
    for(const block of resolved.blocks)block.position.x+=(pushes.get(block.id)||0)*120;
    return resolved;
  }
  return board;
}
export function moveStandaloneBeats(source, ids, dx, dy, options={}) {
  const beats = source.beats.filter(b => ids.has(b.id)), owners = new Set(beats.map(b => b.blockID));
  const blocks = source.blocks.filter(b => owners.has(b.id)), counts = new Map();
  for (const beat of source.beats) counts.set(beat.blockID, (counts.get(beat.blockID) || 0) + 1);
  if (!ids.size || beats.length !== ids.size || beats.some(b => b.locked) || blocks.length !== ids.size ||
      new Set(blocks.map(b => b.layerID)).size !== 1 || blocks.some(b => b.standalone !== true || counts.get(b.id) !== 1) ||
      source.blocks.some(b => owners.has(b.parentID))) throw Error('Select unlocked standalone beats in one layer to move together.');
  const snap = n => Math.sign(n) * Math.round(Math.abs(n) / 10) * 10;
  return moveBlocks(source, owners, snap(dx), snap(dy), options);
}
export function groupBlocks(source, ids, name, id) {
  const board = copy(source), items = board.blocks.filter(b => ids.has(b.id));
  if (items.length !== ids.size || items.length < 1 || items.some(b => blockLocked(board, b.id)) || new Set(items.map(b => b.layerID)).size !== 1 || items.some(b => b.parentID !== items[0].parentID)) throw Error('Select unlocked containers with the same layer and parent.');
  if (!id || board.blocks.some(b => b.id === id)) throw Error('Invalid new group identifier.');
  const position = { x: Math.max(0, Math.min(...items.map(b => b.position.x)) - 18), y: Math.max(32, Math.min(...items.map(b => b.position.y)) - 28) };
  const group = { id, name, layerID: items[0].layerID, position, width: Math.min(2000, Math.max(224, Math.max(...items.map(b => b.position.x + b.width)) - position.x + 18)), collapsed: false, locked: false };
  if (items[0].parentID) group.parentID = items[0].parentID;
  items.forEach(b => { b.parentID = id; }); board.blocks.push(group); return board;
}
export function ungroupBlocks(source, ids) {
  const board = copy(source), groups = board.blocks.filter(b => ids.has(b.id)), byID = new Map(board.blocks.map(b => [b.id, b]));
  if (!ids.size || groups.length !== ids.size || groups.some(g => blockLocked(board, g.id) || (g.containerKind!=='beatGroup' && !board.blocks.some(b => b.parentID === g.id)))) throw Error('Select unlocked groups to ungroup.');
  for(const group of groups.filter(g=>g.containerKind==='beatGroup')){let top=group.position.y;for(const beat of board.beats.filter(b=>b.blockID===group.id).sort((a,b)=>a.order-b.order)){if(beat.locked)throw Error('Unlock the group members.');const loose={...copy(group),id:crypto.randomUUID(),name:'Beat',standalone:true,collapsed:false,position:{x:group.position.x+(beat.position?.x??6)-6,y:beat.position?group.position.y+beat.position.y-24:top}};delete beat.position;delete loose.containerKind;top+=beatSize(beat.title,group.width-12).height+4;beat.blockID=loose.id;board.blocks.push(loose);}}
  for (const block of board.blocks) {
    let parent = block.parentID; while (ids.has(parent)) parent = byID.get(parent)?.parentID;
    if (parent !== block.parentID) {
      if (blockLocked(board, block.id)) throw Error('Unlock the group members before ungrouping.');
      if (parent) block.parentID = parent; else delete block.parentID;
    }
  }
  const occupied = new Set(board.beats.map(b => b.blockID));
  board.blocks = board.blocks.filter(b => !ids.has(b.id) || occupied.has(b.id)); return board;
}
export function deleteBeats(source, ids) {
  const document=copy(source),board=document.project.frontstageWhiteboard,members=board.beats.filter(b=>ids.has(b.id));
  const scenes=new Set(members.map(b=>b.sceneID));
  if(!ids.size||members.length!==ids.size||members.some(b=>b.locked||blockLocked(board,b.blockID))||document.project.beats.some(s=>scenes.has(s.id)&&s.frontstageTextLocked))throw Error('Select unlocked beats and scene scripts before deleting.');
  const affected=new Set(members.map(b=>b.blockID)),pending=[...affected];
  while(pending.length){const owner=board.blocks.find(b=>b.id===pending.pop());if(owner?.parentID&&!affected.has(owner.parentID)){affected.add(owner.parentID);pending.push(owner.parentID);}}
  board.beats=board.beats.filter(b=>!ids.has(b.id));board.dependencies=board.dependencies.filter(e=>!ids.has(e.cause)&&!ids.has(e.effect));
  let removed=true;while(removed){const occupied=new Set(board.beats.map(b=>b.blockID)),parents=new Set(board.blocks.map(b=>b.parentID)),before=board.blocks.length;board.blocks=board.blocks.filter(b=>!affected.has(b.id)||(!b.standalone&&b.containerKind!=='beatGroup')||occupied.has(b.id)||parents.has(b.id));removed=before!==board.blocks.length;}
  const remaining=new Set(board.beats.map(b=>b.sceneID));for(const scene of document.project.beats)if(scenes.has(scene.id)&&!remaining.has(scene.id)){scene.content='';scene.isDisabled=true;}
  return document;
}

export function deleteBlocks(source, ids) {
  const document = copy(source), board = document.project.frontstageWhiteboard, deleting = descendantBlocks(board, ids);
  if (!ids.size || board.blocks.filter(b => deleting.has(b.id)).length !== deleting.size || [...deleting].some(id => blockLocked(board, id))) throw Error('Select unlocked blocks to delete.');
  const beats = new Set(board.beats.filter(b => deleting.has(b.blockID)).map(b => b.id));
  const scenes = new Set(board.beats.filter(b => beats.has(b.id)).map(b => b.sceneID));
  if (board.beats.some(b => beats.has(b.id) && b.locked) || document.project.beats.some(s => scenes.has(s.id) && s.frontstageTextLocked)) throw Error('Unlock the beats and scene scripts before deleting.');
  board.blocks = board.blocks.filter(b => !deleting.has(b.id)); board.beats = board.beats.filter(b => !beats.has(b.id));
  board.dependencies = board.dependencies.filter(e => !beats.has(e.cause) && !beats.has(e.effect));
  const remaining = new Set(board.beats.map(b => b.sceneID));
  for (const scene of document.project.beats) if (scenes.has(scene.id) && !remaining.has(scene.id)) { scene.content = ''; scene.isDisabled = true; }
  return document;
}

export function groupBeats(source, ids, id) {
  const board=copy(source),members=board.beats.filter(b=>ids.has(b.id)),owners=board.blocks.filter(b=>members.some(x=>x.blockID===b.id));
  if(!members.length||members.length!==ids.size||new Set(owners.map(b=>b.layerID)).size!==1||members.some(b=>b.locked||blockLocked(board,b.blockID)))throw Error('Select unlocked beats in one layer.');
  const first=owners[0],group={id,name:'Beat Group',containerKind:'beatGroup',layerID:first.layerID,position:copy(first.position),width:224,collapsed:false,locked:false};
  if(owners.length===1&&!first.standalone&&first.containerKind!=='beatGroup'){group.parentID=first.id;group.position.y+=60;}
  else if(owners.every(b=>b.parentID===first.parentID)&&first.parentID)group.parentID=first.parentID;
  for(const beat of members){beat.blockID=id;delete beat.position;}
  const occupied=new Set(board.beats.map(b=>b.blockID)),parents=new Set(board.blocks.map(b=>b.parentID));
  board.blocks=board.blocks.filter(b=>(!b.standalone&&b.containerKind!=='beatGroup')||occupied.has(b.id)||parents.has(b.id));board.blocks.push(group);return board;
}
// Measure the same styled text used by cards, including fallback fonts and shaping.
let beatMeasure;
const beatMeasurements = new Map();
if (typeof document !== 'undefined') document.fonts?.addEventListener('loadingdone', () => beatMeasurements.clear());
export function beatSize(text,maximumWidth) {
  if (typeof document !== 'undefined' && document.body) {
    const key=JSON.stringify([text,maximumWidth]);
    if(beatMeasurements.has(key))return {...beatMeasurements.get(key)};
    if(!beatMeasure?.isConnected){
      beatMeasure=document.createElement('div');beatMeasure.className='beat beat-size-measure';
      const label=document.createElement('div');label.className='beat-text';beatMeasure.append(label);document.body.append(beatMeasure);
    }
    beatMeasure.firstChild.textContent=text || ' ';
    beatMeasure.style.width='max-content';beatMeasure.style.maxWidth=Math.max(32,maximumWidth)+'px';
    const available=Math.ceil(beatMeasure.getBoundingClientRect().width);
    beatMeasure.style.width=available+'px';
    // Word wrapping can leave a large unused strip. Fit the widest shaped line,
    // rather than keeping the container's maximum width after wrapping.
    const range=document.createRange(),textNode=beatMeasure.firstChild.firstChild;
    const lines=new Map();
    for(const word of (textNode.textContent.matchAll(/\S+/gu))){
      range.setStart(textNode,word.index);range.setEnd(textNode,word.index+word[0].length);
      for(const rect of range.getClientRects()){
      const key=Math.round(rect.top*2),line=lines.get(key);
      lines.set(key,{left:Math.min(line?.left??rect.left,rect.left),right:Math.max(line?.right??rect.right,rect.right)});
      }
    }
    const width=Math.min(available,Math.max(32,Math.ceil(Math.max(0,...[...lines.values()].map(r=>r.right-r.left)))+16));
    beatMeasure.style.width=width+'px';
    const result={width,height:Math.max(26,Math.ceil(beatMeasure.getBoundingClientRect().height))};
    if(beatMeasurements.size>4096)beatMeasurements.clear();
    beatMeasurements.set(key,result);return {...result};
  }
  // Headless model operations have no font renderer; the UI measures again on display.
  const segmenter=new Intl.Segmenter(undefined,{granularity:'grapheme'}),limit=Math.max(1,Math.floor((maximumWidth-18)/6.7)),lines=text.split('\n').map(s=>Math.max(1,[...segmenter.segment(s)].length));
  return {width:Math.max(32,Math.min(limit,Math.max(...lines))*6.7+18),height:Math.max(26,lines.reduce((n,l)=>n+Math.ceil(l/limit),0)*14+12)};
}

export function moveBeatsToLayer(source, ids, layerID, position) {
  const board = copy(source), beats = board.beats.filter(b => ids.has(b.id)).sort((a,b)=>a.order-b.order);
  if (!ids.size || beats.length !== ids.size || beats.some(b=>b.locked || blockLocked(board,b.blockID)) ||
      !board.layers.some(l=>l.id===layerID && !l.locked) || !Number.isFinite(position.x+position.y)) throw Error('Unlock the beats and destination lane.');
  const owners = new Set(beats.map(b=>b.blockID)); let y = Math.max(32,position.y);
  for (const beat of beats) {
    const block = {id:crypto.randomUUID(),name:'Beat',layerID,position:{x:Math.max(0,position.x),y},width:224,standalone:true,collapsed:false,locked:false};
    board.blocks.push(block); beat.blockID=block.id;delete beat.position; y+=beatSize(beat.title,212).height+28;
  }
  board.blocks=board.blocks.filter(b=>!owners.has(b.id)||(!b.standalone&&b.containerKind!=='beatGroup')||board.beats.some(x=>x.blockID===b.id)||board.blocks.some(x=>x.parentID===b.id));
  return board;
}
export function spatialOrder(source) {
  const board=copy(source), blocks=new Map(board.blocks.map(b=>[b.id,b])), layers=new Map(board.layers.map((l,i)=>[l.id,i]));
  [...board.beats].sort((a,b)=>{const x=blocks.get(a.blockID),y=blocks.get(b.blockID);return (x.position.x+(a.position?.x??6))-(y.position.x+(b.position?.x??6)) || layers.get(x.layerID)-layers.get(y.layerID) || x.position.y-y.position.y || a.order-b.order || a.id.localeCompare(b.id);}).forEach((b,i)=>b.order=i);
  return board;
}

// Forward-only ripple keeps intentional time gaps. Compaction is a separate explicit action.
export function resolveCausalTime(source) {
  const board=copy(source),beats=new Map(board.beats.map(b=>[b.id,b])),locked=lockedBlockIDs(board);
  const unusedLayers=new Set(board.layers.filter(l=>l.unused).map(l=>l.id));
  const unused=new Set(board.blocks.filter(b=>unusedLayers.has(b.layerID)).map(b=>b.id)),incoming=new Map();
  for(const edge of board.dependencies.filter(e=>!e.reference)){if(!incoming.has(edge.effect))incoming.set(edge.effect,[]);incoming.get(edge.effect).push(edge.cause);}
  for(const id of causalOrder(board)){
    const beat=beats.get(id);if(beat.omitted||unused.has(beat.blockID))continue;
    const required=Math.max(0,...(incoming.get(id)||[]).map(id=>beats.get(id)).filter(b=>!b.omitted&&!unused.has(b.blockID)).map(b=>b.start+b.duration));
    if(beat.start<required){if(beat.locked||locked.has(beat.blockID))throw Error(`${beat.title} is locked and blocks ripple`);beat.start=required;}
  }
  return board;
}

export function dropBeats(source, ids, targetID) {
  let board=copy(source);const target=board.beats.find(b=>b.id===targetID),members=board.beats.filter(b=>ids.has(b.id));
  if(!target||ids.has(targetID)||!members.length||members.length!==ids.size||[target,...members].some(b=>b.locked||blockLocked(board,b.blockID)))throw Error('Select unlocked beats and a different target.');
  const owner=board.blocks.find(b=>b.id===target.blockID);
  for(const beat of members){beat.blockID=owner.id;delete beat.position;beat.order=Math.max(...board.beats.map(b=>b.order))+1;}
  if(owner.standalone){owner.standalone=false;owner.containerKind='beatGroup';owner.name='Beat Group';}
  else if(owner.containerKind!=='beatGroup')board=groupBeats(board,new Set([...ids,targetID]),crypto.randomUUID());
  return pruneEmptyBeatContainers(board);
}
export function pruneEmptyBeatContainers(board) {
  const occupied=new Set(board.beats.map(b=>b.blockID)),parents=new Set(board.blocks.map(b=>b.parentID));
  board.blocks=board.blocks.filter(b=>(!b.standalone&&b.containerKind!=='beatGroup')||occupied.has(b.id)||parents.has(b.id));return board;
}

export function usesBlocks(board,layerID){return board.layers.find(l=>l.id===layerID)?.useBlocks===true;}

export function nestGroups(source,ids,targetID,dx,dy){
  const board=copy(source),target=board.blocks.find(b=>b.id===targetID),moving=descendantBlocks(board,ids);
  if(!ids.size||!target||target.standalone||target.containerKind==='beatGroup'||blockLocked(board,targetID)||moving.has(targetID)||[...ids].some(id=>board.blocks.find(b=>b.id===id)?.containerKind!=='beatGroup')||[...moving].some(id=>blockLocked(board,id)))throw Error('Drop unlocked groups into a block without creating a container loop.');
  for(const block of board.blocks)if(moving.has(block.id)){if(ids.has(block.id)&&!moving.has(block.parentID))block.parentID=targetID;block.layerID=target.layerID;}
  return moveBlocks(board,ids,dx,dy,{layerID:target.layerID,ripple:false});
}

export function splitGroupAt(source,beatID){
 const board=copy(source),beat=board.beats.find(b=>b.id===beatID),group=board.blocks.find(b=>b.id===beat?.blockID);
 if(!group||group.containerKind!=='beatGroup'||lockedBlockIDs(board).has(group.id))throw Error('Choose an unlocked group member.');
 const members=board.beats.filter(b=>b.blockID===group.id).sort((a,b)=>a.order-b.order),index=members.findIndex(b=>b.id===beatID);
 if(index<=0||members.slice(index).some(b=>b.locked))throw Error('Split after the first beat and unlock group members.');
 const next={...copy(group),id:crypto.randomUUID(),name:group.name+' (2)',position:{x:group.position.x+group.width+24,y:group.position.y}};board.blocks.push(next);
 for(const b of members.slice(index)){b.blockID=next.id;delete b.position;}return board;
}
export function mergeContainers(source,ids){
 const board=copy(source),items=board.blocks.filter(b=>ids.has(b.id)).sort((a,b)=>a.position.x-b.position.x),target=items[0],locked=lockedBlockIDs(board);
 if(items.length<2||items.length!==ids.size||items.some(b=>b.layerID!==target.layerID||b.parentID!==target.parentID||b.containerKind!==target.containerKind||b.standalone||locked.has(b.id))||board.beats.some(b=>ids.has(b.blockID)&&b.locked))throw Error('Select unlocked sibling groups or blocks of the same kind.');
 for(const beat of board.beats.filter(b=>ids.has(b.blockID))){const source=items.find(b=>b.id===beat.blockID),p=beat.position??{x:6,y:24};if(target.containerKind==='beatGroup')delete beat.position;else beat.position={x:Math.max(6,source.position.x+p.x-target.position.x),y:Math.max(24,source.position.y+p.y-target.position.y)};beat.blockID=target.id;}
 for(const b of board.blocks)if(ids.has(b.parentID))b.parentID=target.id;
 target.width=Math.min(2000,Math.max(...items.map(b=>b.position.x+b.width-target.position.x)));target.synopsis=items.map(b=>b.synopsis).filter(Boolean).join('\n');board.blocks=board.blocks.filter(b=>!ids.has(b.id)||b.id===target.id);return board;
}
export function pushBoard(source,x,distance){
 const roots=source.blocks.filter(b=>!b.parentID&&b.position.x>=x);if(!roots.length)return copy(source);let delta=distance;
 if(delta<0)for(const root of roots){const edge=Math.max(0,...source.blocks.filter(b=>!b.parentID&&b.layerID===root.layerID&&b.position.x<x).map(b=>b.position.x+b.width+12));delta=Math.max(delta,Math.min(0,edge-root.position.x));}
 return moveBlocks(source,new Set(roots.map(b=>b.id)),delta,0,{ripple:false});
}
export function splitBlockAt(source,id,x){
 const board=copy(source),block=board.blocks.find(b=>b.id===id),locked=lockedBlockIDs(board);
 if(!block||block.containerKind==='beatGroup'||block.standalone||locked.has(id)||x<=block.position.x+12)throw Error('Split inside an unlocked block.');
 const children=board.blocks.filter(b=>b.parentID===id&&b.position.x>=x),beats=board.beats.filter(b=>b.blockID===id&&block.position.x+(b.position?.x??6)>=x);
 if(!children.length&&!beats.length)throw Error('Choose a split point with content to its right.');if(children.some(b=>locked.has(b.id))||beats.some(b=>b.locked))throw Error('Unlock the content before splitting.');
 const next={...copy(block),id:crypto.randomUUID(),name:block.name+' (2)',position:{...block.position,x},width:Math.max(140,block.position.x+block.width-x)};
 for(const child of children)child.parentID=next.id;for(const beat of beats){const p=beat.position??{x:6,y:24};beat.blockID=next.id;beat.position={x:Math.max(6,block.position.x+p.x-x),y:p.y};}block.width=Math.max(140,x-block.position.x-12);board.blocks.push(next);return board;
}
export function reorderTimelineBeats(source,ids,targetID){
 const board=copy(source),ordered=[...board.beats].sort((a,b)=>a.order-b.order),moving=ordered.filter(b=>ids.has(b.id)),locked=lockedBlockIDs(board);
 if(!moving.length||moving.length!==ids.size||ids.has(targetID)||!ordered.some(b=>b.id===targetID)||moving.some(b=>b.locked||locked.has(b.blockID)))throw Error('Choose unlocked beats and a different insertion point.');
 const sequence=ordered.filter(b=>!ids.has(b.id));sequence.splice(sequence.findIndex(b=>b.id===targetID),0,...moving);
 for(const group of board.blocks.filter(b=>b.containerKind==='beatGroup')){const indices=sequence.flatMap((b,i)=>b.blockID===group.id?[i]:[]);if(indices.length&&indices.at(-1)-indices[0]+1!==indices.length)throw Error("Keep a group's beats together, or convert it to free beats before intercutting.");}
 sequence.forEach((b,i)=>{if(b.order!==i&&(b.locked||locked.has(b.blockID)))throw Error('This reorder would move a locked beat.');b.order=i;});
 for(const block of board.blocks){const descendants=descendantBlocks(board,new Set([block.id])),members=board.beats.filter(b=>descendants.has(b.blockID));if(!members.length)continue;const first=Math.min(...members.map(b=>b.order)),x=40+first*60;if(x!==block.position.x&&locked.has(block.id))throw Error('This reorder would move a locked container.');block.position.x=x;
 for(const b of board.beats.filter(b=>b.blockID===block.id)){if(block.containerKind==='beatGroup')delete b.position;else if(!block.standalone)b.position={x:6+(b.order-first)*60,y:b.position?.y??24};}}
 return board;
}
