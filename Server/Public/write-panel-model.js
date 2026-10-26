import * as model from './workspace-model.js';
import {reorderTimelineBeats} from './board-operations.js';
export function sceneCards(document) {
  const segments=model.scriptSegments(document,{includeInactive:true}), ordered=[...model.board(document).beats].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id));
  return [...new Set([...segments.map(s=>s.scene.id),...document.project.beats.map(s=>s.id)])].map(id=>({scene:model.scene(document,id),number:segments.find(s=>s.scene.id===id)?.number||model.scene(document,id).sceneNumber||'',beats:ordered.filter(b=>b.sceneID===id)}));
}
export function writableScene(document,id) {const s=model.scene(document,id);if(s.frontstageTextLocked)throw Error('Unlock the scene before editing.');return s;}
export function updateSceneSummary(document,id,summary) {writableScene(document,id).summary=summary;}
function owner(document,id) {return id==null?document.project:writableScene(document,id);}
function notes(document,id) {const o=owner(document,id),key=id==null?'globalNotes':'notes';if(o[key]!=null&&!Array.isArray(o[key]))throw Error('Unsupported imported notes are preserved.');return o[key]||=[];}
export function editableNote(note) {return !!note&&typeof note.id==='string'&&typeof note.content==='string'&&!/<(?:audio|video|iframe|object)\b/i.test(note.content)&&!note.audio&&!note.audioUrl&&(!note.type||note.type==='text');}
export function addNote(document,id,content='',color='#fff4bc') {const value={id:crypto.randomUUID(),content,color,timestamp:Date.now()};notes(document,id).push(value);return value.id;}
export function updateNote(document,id,noteID,patch) {const note=notes(document,id).find(n=>n.id===noteID);if(!editableNote(note))throw Error('This imported note is read-only or no longer exists.');for(const key of ['content','color'])if(typeof patch[key]==='string')note[key]=patch[key];}
export function removeNote(document,id,noteID) {const list=notes(document,id),i=list.findIndex(n=>n.id===noteID);if(i<0)throw Error('Note not found.');list.splice(i,1);}
export function moveNote(document,id,noteID,offset) {const list=notes(document,id),i=list.findIndex(n=>n.id===noteID);if(i>=0&&i+offset>=0&&i+offset<list.length)list.splice(i+offset,0,list.splice(i,1)[0]);}
export function moveRequirement(document,id,entry,category) {
  if(!model.categories.includes(category))throw Error('Choose a supported category.');
  const s=writableScene(document,id),data=s[entry.storage],source=data?.[entry.bucket];
  if(!source||source[entry.index]==null)throw Error('The breakdown item no longer exists.');
  const old=source[entry.index];if(entry.id&&old.id!==entry.id)throw Error('The item changed; select it again.');
  const item=typeof old==='string'?{name:old}:old;source.splice(entry.index,1);item.category=category;(data[category]||=[]).push(item);
}
export function reorderScene(document,id,targetID) {
  const ordered=[...model.board(document).beats].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id)), members=ordered.filter(b=>b.sceneID===id),indices=members.map(b=>ordered.indexOf(b));
  writableScene(document,id);writableScene(document,targetID);
  if(!members.length||indices.at(-1)-indices[0]+1!==indices.length)throw Error('Interleaved scenes cannot move as a single card.');
  const target=ordered.find(b=>b.sceneID===targetID);if(!target)throw Error('The destination has no beats.');
  document.project.frontstageWhiteboard=reorderTimelineBeats(model.board(document),new Set(members.map(b=>b.id)),target.id);
}
export const normalizedCategory=entry=>entry.category||({props:'PROPS',costume:'WARDROBE',practical:'SFX',sound:'SOUND',cast:'CAST',location:'LOCATION',vfx:'VFX'}[entry.bucket]||entry.bucket);
// Imported HTML is rendered through an allowlist, never rewritten unless explicitly edited.
export function safeNoteHTML(html) {
  const source=document.createElement('template');source.innerHTML=typeof html==='string'?html:'';
  const clean=document.createElement('div');
  function copy(node,parent){if(node.nodeType===3){parent.append(document.createTextNode(node.textContent));return;}if(node.nodeType!==1)return;if(['SCRIPT','STYLE','IFRAME','OBJECT','SVG','MATH'].includes(node.tagName))return;const allowed=['P','DIV','BR','B','STRONG','I','EM','U','S','UL','OL','LI','BLOCKQUOTE'];const target=allowed.includes(node.tagName)?document.createElement(node.tagName):parent;if(target!==parent)parent.append(target);for(const child of node.childNodes)copy(child,target);}
  for(const node of source.content.childNodes)copy(node,clean);return clean.innerHTML;
}
