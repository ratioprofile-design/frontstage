import {requiredWriteFeatures,validateServerFeatures} from './feature-compatibility.js';
import {validateTypography,applyTypography,popupTypography} from './script-typography.js';
import {eraseBoardDrawing} from './board-drawing.js';
import {parseProjectFile,projectFilename} from './project-files.js';
import {insertScriptScene} from './continuous-script.js';
import {isSceneModel,syncSceneMetadata,validateSceneModel,convertSceneCopy,duplicateBeat} from './scene-model.js';
import {pullOutBeats,validateInclusion} from './script-inclusion.js';
import {createScriptFilter,mountScriptFilter,matchesScriptFilter,gapLabel} from './script-filter.js';
import { timelineModel, mountTimeline, timelinePreferences } from './story-timeline.js';
import { mountWorkspaces } from './workspaces.js';
import { splitAtCaret, screenplayToolbar, sluglineFields, characterNames, screenplaySelection, restoreScreenplaySelection } from './screenplay-editor.js';
import {dialogueSeed} from './dialogue-rules.js';
import { splitBeat, scriptSegments, heading, captureRevision, restoreRevision } from './workspace-model.js';
import { mergeDocuments } from './merge.js';
import { apiOrigin as configuredOrigin } from './config.js';
import { causalOrder as orderCauses, compactCausalTime, groupBlocks, ungroupBlocks, moveBlocks, moveStandaloneBeats, descendantBlocks, deleteBlocks, deleteBeats, validateBoard, groupBeats, beatSize, moveBeatsToLayer, spatialOrder, dropBeats, pruneEmptyBeatContainers, usesBlocks, nestGroups, splitGroupAt, mergeContainers, pushBoard, splitBlockAt, reorderTimelineBeats } from './board-operations.js';

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js', { updateViaCache: 'none' }).catch(() => {});

const $ = id => document.getElementById(id);
const clone = value => structuredClone(value);
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const uuid = () => crypto.randomUUID();
let token = '', current = null, doc = null, base = null, selected = null, editorID = null, source = null;
let dirty = false, syncing = false, timer = null, pendingConflict = null;
let documentEpoch = 0;
let apiOrigin = '';
let localMode = false;
let selectedBlocks = new Set(), selectedBeats = new Set();
function loadTimelinePreferences(expanded){try{return timelinePreferences(expanded,JSON.parse(localStorage.getItem('frontstage-timeline-'+(expanded?'full':'mini'))));}catch{return timelinePreferences(expanded);}}
let timelineWindow=null,timelineWindowRoot=null;
const timelineState={expanded:false,time:0,...loadTimelinePreferences(false)};
function saveTimelinePreferences(){try{localStorage.setItem('frontstage-timeline-'+(timelineState.expanded?'full':'mini'),JSON.stringify({...timelineState,collapsed:[...timelineState.collapsed],hidden:[...timelineState.hidden]}));}catch{}}
const scriptFilter=createScriptFilter();let filterProjectID;
const reader={display:'Expand All',characters:true,tags:true,synopsis:false,boundaries:false,margin:'Compact Margins',zoom:1,filter:'',follow:false};
$('server-address').value = configuredOrigin || localStorage.getItem('frontstage-server') || '';
function setServer() {
  const value = $('server-address').value.trim();
  if (!value) { apiOrigin = ''; localStorage.removeItem('frontstage-server'); return; }
  const url = new URL(value);
  const local = ['127.0.0.1', 'localhost', '[::1]'];
  if ((url.protocol !== 'https:' && !(url.protocol === 'http:' && local.includes(url.hostname) && local.includes(location.hostname))) ||
      url.username || url.password || url.search || url.hash || !['', '/'].includes(url.pathname)) throw Error('Enter the shared server’s HTTPS address without a path or credentials.');
  apiOrigin = url.origin; localStorage.setItem('frontstage-server', apiOrigin);
}
const history = [];
const future = [];
const historyFocus=new WeakMap();let beforeInputFocus=null;
let lastHistoryKey=null,lastHistoryTime=0;
function captureWriterFocus(){const root=document.activeElement;if(!root?.isContentEditable)return null;let selector;if(root.matches('.continuous-editor'))selector='.continuous-editor';else if(root.closest('[data-note-id]'))selector='[data-note-id="'+CSS.escape(root.closest('[data-note-id]').dataset.noteId)+'"] .note-content';else if(root.closest('.beat-popup[data-beat-id]'))selector='.beat-popup[data-beat-id="'+CSS.escape(root.closest('.beat-popup').dataset.beatId)+'"] [data-field="snippet-editor"]';else return null;const desk=root.closest('.continuous-desk');return {selector,bookmark:screenplaySelection(root),scroll:desk?{x:desk.scrollLeft,y:desk.scrollTop}:null};}
function restoreWriterFocus(saved){const root=saved&&document.querySelector(saved.selector);if(!root||!restoreScreenplaySelection(root,saved.bookmark))return;const desk=root.closest('.continuous-desk');if(desk&&saved.scroll){desk.scrollLeft=saved.scroll.x;desk.scrollTop=saved.scroll.y;}}
document.addEventListener('beforeinput',()=>{beforeInputFocus=captureWriterFocus();},true);
document.addEventListener('keydown',event=>{if(!doc||event.isComposing||event.target.isComposing||!(event.ctrlKey||event.metaKey)||['INPUT','TEXTAREA'].includes(event.target.tagName))return;const key=event.key.toLowerCase();if(key!=='z'&&!(key==='y'&&event.ctrlKey&&!event.metaKey))return;event.preventDefault();event.stopImmediatePropagation();if(key==='y'||event.shiftKey)restoreHistory(future,history);else restoreHistory(history,future);},true);
const status = text => { $('status').textContent = text; };
function element(tag, text, className) { const e = document.createElement(tag); if (text !== undefined) e.textContent = text; if (className) e.className = className; return e; }
function list(value) { return [...new Set(value.split(',').map(s => s.trim()).filter(Boolean))]; }
const legacyCredentialKeys = new Set(['geminiapikey', 'openrouterkey', 'openrouterapikey', 'tokenrouterapikey', 'apikey', 'r2accesskeyid', 'r2secretaccesskey', 'vite_r2_access_key_id', 'vite_r2_secret_access_key']);
function stripLegacyCredentials(value) {
  if (Array.isArray(value)) return value.map(stripLegacyCredentials);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).filter(([key]) => !legacyCredentialKeys.has(key.toLowerCase())).map(([key, child]) => [key, stripLegacyCredentials(child)]));
  return value;
}
function cleanHTML(source) {
  const parsed = new DOMParser().parseFromString(source, 'text/html');
  const allowed = new Set(['DIV', 'P', 'BR', 'B', 'STRONG', 'I', 'EM', 'U', 'SPAN']);
  function clean(node) {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.textContent);
    const fragment = document.createDocumentFragment();
    if (node.nodeType !== Node.ELEMENT_NODE || ['SCRIPT', 'STYLE', 'IFRAME', 'OBJECT'].includes(node.tagName)) return fragment;
    const target = allowed.has(node.tagName) ? document.createElement(node.tagName.toLowerCase()) : fragment;
    if (target instanceof HTMLElement) target.className = [...node.classList].filter(c => /^sc-(line|action|character|dialogue|parenthetical|transition|shot|lyrics|slugline|dual-left|dual-right|rev)$/.test(c)).join(' ');
    if (target instanceof HTMLElement && /^[A-Za-z0-9_-]{1,120}$/.test(node.getAttribute('data-dual-pair')||'')) target.setAttribute('data-dual-pair',node.getAttribute('data-dual-pair'));
    for (const child of node.childNodes) target.append(clean(child));
    return target;
  }
  const result = document.createElement('div');
  for (const child of parsed.body.childNodes) result.append(clean(child));
  return result.innerHTML;
}
function plain(html) { const node = document.createElement('div'); node.innerHTML = cleanHTML(html); return node.textContent; }
async function api(path, method = 'GET', body) {
  const origin=apiOrigin,sessionToken=token;
  if(body?.document&&requiredWriteFeatures(body.document).length){
    const health=await fetch(origin+'/health');if(!health.ok||!(health.headers.get('Content-Type')||'').includes('application/json'))throw Error('Update the DOT shared server before syncing this project. Local changes remain saved.');
    validateServerFeatures(body.document,(await health.json()).supportedFeatures||[]);
    if(origin!==apiOrigin||sessionToken!==token)throw Error('The shared connection changed. Local changes remain saved.');
  }
  const response = await fetch(origin + path, { method, headers: { 'Content-Type': 'application/json', ...(sessionToken ? { Authorization: `Bearer ${sessionToken}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!(response.headers.get('Content-Type') || '').includes('application/json') && response.status !== 204) throw Error('Shared service unavailable. Enter your DOT server address to sign in.');
  const data = response.status === 204 ? null : await response.json();
  if (!response.ok && response.status !== 409) throw Error(data?.reason || `Request failed (${response.status})`);
  return { data, status: response.status };
}
const database = new Promise((resolve, reject) => {
  const request = indexedDB.open('frontstage-offline', 1);
  request.onupgradeneeded = () => request.result.createObjectStore('projects', { keyPath: 'id' });
  request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
});
async function saveLocal() {
  if (!current || !doc) return;
  const snapshot = { id: current.id, doc: clone(doc), base: clone(base), revision: current.revision, dirty, local: !!current.local, name: doc.name, serverOrigin: current.local ? null : apiOrigin || location.origin };
  const db = await database;
  return new Promise((resolve, reject) => { const tx = db.transaction('projects', 'readwrite'); tx.objectStore('projects').put(snapshot); tx.oncomplete = resolve; tx.onerror = () => reject(tx.error); });
}
async function localCopy(id) {
  const db = await database;
  return new Promise((resolve, reject) => { const r = db.transaction('projects').objectStore('projects').get(id); r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });
}
async function loadLocalProjects() {
  localMode = true;
  const db = await database;
  const copies = await new Promise((resolve, reject) => { const request = db.transaction('projects').objectStore('projects').getAll(); request.onsuccess = () => resolve(request.result.filter(p => p.local)); request.onerror = () => reject(request.error); });
  $('project-list').replaceChildren();
  for (const copy of copies) {
    const button = element('button', `${copy.name || 'Untitled Story'} · on this device`);
    button.onclick = () => openLocalProject(copy.id).catch(e => status(e.message)); $('project-list').append(button);
  }
  $('account').hidden = true; $('projects').hidden = false; $('workspace').hidden = true; $('project-toolbar').hidden = true;
  $('logout').textContent = 'Sign In'; status('Local projects · saved in this browser');
  if (!copies.length) await createLocalProject('Untitled Story');
}
async function recoverSharedDrafts() {
  await saveLocal();
  const db=await database;
  const copies=await new Promise((resolve,reject)=>{const request=db.transaction('projects').objectStore('projects').getAll();request.onsuccess=()=>resolve(request.result.filter(p=>!p.local));request.onerror=()=>reject(request.error);});
  localMode=true;closeEditors();$('project-list').replaceChildren();
  for(const copy of copies){const button=element('button',`${copy.name||'Untitled Story'} · recover ${copy.dirty?'unsynced draft':'cached copy'}`);button.onclick=()=>createLocalProject(copy.name,initializeBoard(clone(copy.doc))).catch(e=>status(e.message));$('project-list').append(button);}
  $('account').hidden=true;$('projects').hidden=false;$('workspace').hidden=true;$('project-toolbar').hidden=true;$('logout').textContent='Sign In';
  status(copies.length?'Recovery creates a separate local project. Sign in to resume sharing; the original draft is retained.':'No shared drafts have been saved on this device.');
}
$('recover-shared').onclick=()=>recoverSharedDrafts().catch(e=>status(e.message));
function emptyDocument(name) { const project={beats:[],nextId:1,frontstageSceneModel:'oneBeatPerScene'};try{const saved=JSON.parse(localStorage.getItem('frontstage-default-script-layout'));if(saved)project.frontstageScriptLayout=validateTypography(saved);}catch{status('Saved typography defaults could not be loaded. Standard settings were used for this new project.');}return initializeBoard({format:'frontstage',version:1,name,project}); }
async function createLocalProject(name, document = emptyDocument(name)) {
  const id = 'local-' + uuid(), db = await database;
  await new Promise((resolve, reject) => { const tx = db.transaction('projects', 'readwrite'); tx.objectStore('projects').put({ id, doc: document, base: clone(document), revision: 0, dirty: false, local: true, name: document.name }); tx.oncomplete = resolve; tx.onerror = () => reject(tx.error); });
  await openLocalProject(id);
}
async function openLocalProject(id) {
  const epoch = ++documentEpoch; clearTimeout(timer);
  const copy = await localCopy(id); if (epoch !== documentEpoch || !copy?.local) return;
  const nextDocument = initializeBoard(clone(copy.doc)), nextBase = stripLegacyCredentials(clone(copy.base));
  current = { id, name: copy.name, access: 'owner', revision: 0, local: true }; localMode = true;
  doc = nextDocument; base = nextBase; dirty = false;
  history.length = 0; future.length = 0; selectedBlocks.clear(); selectedBeats.clear(); selected = null; source = null; editorID = null; pendingConflict = null;
  closeEditors(); $('conflict').hidden = true; $('account').hidden = true; $('projects').hidden = true; $('workspace').hidden = false;
  $('logout').textContent = 'Sign In'; render(); status('Saved on this device');
}
function board() { return doc.project.frontstageWhiteboard; }
function initializeBoard(document) {
  document = stripLegacyCredentials(document);
  if (document.format !== 'frontstage') document = { format: 'frontstage', version: 1, name: 'Imported Story', project: document };
  if (document.version !== 1 || !Array.isArray(document.project.beats)) throw Error('Unsupported project format');
  if (document.project.beats.some(beat => !Number.isSafeInteger(beat.id) || beat.id < 0)) throw Error('This project uses numeric identifiers outside browser precision. Open it with the native Swift client.');
  if (new Set(document.project.beats.map(b => b.id)).size !== document.project.beats.length || document.project.beats.some(b => typeof b.title !== 'string' || typeof b.content !== 'string')) throw Error('Each scene needs a unique identifier, title and script text.');
  if (!document.project.frontstageWhiteboard) {
    const beats = document.project.beats;
    document.project.frontstageWhiteboard = {
      version: 1, layers: [{ ...(beats.length?{}:{useBlocks:false}), id: 'main', name: 'Main Layer', height: 360, collapsed: false, locked: false, unused: false }, { id: 'unused', name: 'Unused', height: 300, collapsed: false, locked: false, unused: true }],
      blocks: beats.map((b, i) => ({ id: `block-${b.id}`, name: b.title, layerID: 'main', position: { x: b.x || i * 260, y: 60 }, width: 224, collapsed: false, locked: false })),
      beats: beats.map((b, i) => ({ id: `scene-${b.id}`, sceneID: b.id, blockID: `block-${b.id}`, title: b.title, synopsis: b.summary || '', html: b.content || '', kind: 'story', color: '#a34eae', characters: b.characters || [], tags: [], mustBeCaused: false, omitted: !!b.isDisabled, locked: false, order: i, start: i * 1.5, duration: 1.5 })),
      dependencies: (document.project.connections || []).filter(l => beats.some(b => b.id === l.from) && beats.some(b => b.id === l.to)).map(l => ({ id: uuid(), cause: `scene-${l.from}`, effect: `scene-${l.to}`, reason: l.label || '', reference: l.frontstageKind === 'reference' })),
      strokes: [], viewport: { origin: { x: 0, y: 0 }, zoom: 1 }
    };
  }
  if (document.project.frontstageWhiteboard.version !== 1) throw Error('Unsupported whiteboard version');
  validateInclusion(document);validateSceneModel(document);
  validateBoard(document.project.frontstageWhiteboard, new Set(document.project.beats.map(b => b.id)));
  const native = document.project.frontstageWhiteboard, unused = new Set(native.layers.filter(l => l.unused).map(l => l.id)), inactive = new Set(native.blocks.filter(b => unused.has(b.layerID)).map(b => b.id));
  const projections = new Map();
  for (const beat of [...native.beats].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))) {
    if (!projections.has(beat.sceneID)) projections.set(beat.sceneID, '');
    if (!beat.omitted && !inactive.has(beat.blockID)) projections.set(beat.sceneID, projections.get(beat.sceneID) + beat.html);
  }
  for (const scene of document.project.beats) if (projections.has(scene.id) && projections.get(scene.id) !== scene.content) throw Error('The scene script differs from its linked snippets. Reconcile the source text before importing this project.');
  return document;
}
function unused(beat) { const block = board().blocks.find(b => b.id === beat.blockID); return board().layers.find(l => l.id === block?.layerID)?.unused; }
function locked(beat) { let block = board().blocks.find(b => b.id === beat.blockID); const visited = new Set(); if (beat.locked) return true; while (block && !visited.has(block.id)) { if (block.locked || board().layers.find(l => l.id === block.layerID)?.locked) return true; visited.add(block.id); block = board().blocks.find(b => b.id === block.parentID); } return false; }
function compileSnippets() {
  for (const scene of doc.project.beats) {
    const linked = board().beats.filter(b => b.sceneID === scene.id);
    if (!linked.length) continue;
    const active = linked.filter(b => !b.omitted && !unused(b)).sort((a, b) => a.order - b.order);
    const content = active.map(b => b.html).join('');
    if (scene.frontstageTextLocked && scene.content !== content) throw Error('Unlock the scene script before changing its snippet text or inclusion.');
    scene.content = content; scene.isDisabled = active.length === 0;
    scene.characters = [...new Set(active.flatMap(b => b.characters))].sort();
  }
}
function edit(action,historyKey=null) {
  if (!doc || current.access === 'reader') return false;
  const previous = clone(doc);
  historyFocus.set(previous,beforeInputFocus||captureWriterFocus());beforeInputFocus=null;
  try { action(); syncSceneMetadata(doc);validateSceneModel(doc);validateInclusion(doc); validateBoard(board(), new Set(doc.project.beats.map(s => s.id))); compileSnippets(); if (equal(previous, doc)) return true; const now=Date.now(),key=historyKey||(document.activeElement?.matches('.note-content')?'note:'+document.activeElement.closest('[data-note-id]')?.dataset.noteId:null);if(!key||key!==lastHistoryKey||now-lastHistoryTime>=1000||future.length)history.push(previous);lastHistoryKey=key;lastHistoryTime=now;future.length = 0; if (history.length > 40) history.shift(); dirty = true; saveLocal().catch(e => status(`Local save failed: ${e.message}`)); render(); clearTimeout(timer); timer = setTimeout(sync, 800); return true; }
  catch (error) { doc = previous; render(); status(error.message); return false; }
}
function restoreHistory(from, to) {
  if (!doc || current.access === 'reader' || !from.length) return;
  lastHistoryKey=null;
  const fallback=captureWriterFocus(),next=clone(doc);historyFocus.set(next,fallback);to.push(next); doc = from.pop(); dirty = true;
  refreshEditors(true);
  saveLocal().catch(e => status(`Local save failed: ${e.message}`)); render(); clearTimeout(timer); timer = setTimeout(sync, 800);
  restoreWriterFocus(historyFocus.get(doc)||fallback);
}
async function sync() {
  if (current?.local) {
    const epoch = documentEpoch;
    try { dirty = false; await saveLocal(); if (epoch === documentEpoch) status('Saved on this device'); }
    catch (error) { if (epoch === documentEpoch) { dirty = true; status(`Local save failed: ${error.message}`); } }
    return;
  }
  if (!current || current.access === 'reader' || !dirty || syncing || pendingConflict) return;
  syncing = true; const sent = clone(doc);
  const epoch = documentEpoch, projectID = current.id, revision = current.revision;
  status('Syncing…');
  try {
    await saveLocal();
    if (epoch !== documentEpoch) return;
    const { data, status: code } = await api(`/api/projects/${projectID}`, 'PUT', { expectedRevision: revision, changeID: uuid(), document: sent, supportedFeatures: ['elementTypography','productionBaselines','dualDialogue'] });
    if (epoch !== documentEpoch || current?.id !== projectID) return;
    if (code === 409) {
      const result = mergeDocuments(base, doc, data.snapshot.document);
      if (result.conflicts.length) { pendingConflict = data.snapshot; $('conflict-fields').textContent = result.conflicts.join('\n'); $('conflict').hidden = false; status('Conflict: local copy retained'); }
      else { doc = initializeBoard(result.value); base = clone(data.snapshot.document); current.revision = data.snapshot.revision; dirty = true; render(); }
    } else {
      base = clone(data.snapshot.document); current.revision = data.snapshot.revision; current.access = data.snapshot.access;
      dirty = !equal(doc, sent); status(dirty ? 'More changes pending' : `Synced · revision ${current.revision}`);
    }
    await saveLocal();
  } catch (error) { if (epoch === documentEpoch) status(`Offline / sync failed · local copy retained: ${error.message}`); }
  finally { syncing = false; if (dirty && !pendingConflict && navigator.onLine) { clearTimeout(timer); timer = setTimeout(sync, 3000); } }
}
async function loadProjects() {
  localMode = false; $('logout').textContent = 'Sign Out';
  const { data } = await api('/api/projects'); $('project-list').replaceChildren();
  for (const project of data) { const button = element('button', `${project.name} · ${project.access} · revision ${project.revision}`); button.onclick = () => openProject(project.id).catch(e => status(e.message)); $('project-list').append(button); }
  $('account').hidden = true; $('projects').hidden = false; $('workspace').hidden = true; $('project-toolbar').hidden = true;
}
async function openProject(id) {
  const epoch = ++documentEpoch; clearTimeout(timer);
  const { data } = await api(`/api/projects/${id}`), offline = await localCopy(id);
  if (epoch !== documentEpoch) return;
  const nextBase = clone(offline?.dirty ? offline.base : data.document), nextDocument = initializeBoard(clone(offline?.dirty ? offline.doc : data.document));
  current = data; history.length = 0; future.length = 0; selectedBlocks.clear(); selectedBeats.clear(); selected = null; editorID = null; closeEditors();
  pendingConflict = null; source = null; $('conflict').hidden = true;
  base = nextBase; doc = nextDocument; dirty = !!offline?.dirty || !equal(doc, data.document);
  if (offline?.dirty) current.revision = offline.revision;
  $('projects').hidden = true; $('workspace').hidden = false; render(); status(dirty ? 'Local changes ready to sync' : `Synced · revision ${current.revision}`);
  if (dirty) sync();
}
function choose(id, multiple = false) {
  if (source && source !== id) {
    const cause = source; source = null;
    edit(() => { if (board().dependencies.some(e => e.cause === cause && e.effect === id)) throw Error('Already connected'); board().dependencies.push({ id: uuid(), cause, effect: id, reason: '', reference: false }); causalOrder(); });
  }
  selectedBlocks.clear();
  if (multiple) { if (selectedBeats.has(id)) selectedBeats.delete(id); else selectedBeats.add(id); }
  else selectedBeats = new Set([id]);
  selected = id; render(); highlightScript(true); $('canvas').focus({preventScroll:true});
}
function causalOrder() {
  return orderCauses(board());
}
function resolve() {
  for (const id of causalOrder()) {
    const beat = board().beats.find(b => b.id === id); if (beat.omitted || unused(beat)) continue;
    const starts = board().dependencies.filter(e => !e.reference && e.effect === id).map(e => board().beats.find(b => b.id === e.cause)).filter(b => b && !b.omitted && !unused(b)).map(b => b.start + b.duration);
    const required = Math.max(0, ...starts);
    if (beat.start < required) { if (locked(beat)) throw Error(`${beat.title} is locked and blocks ripple`); beat.start = required; }
  }
}
function storyIssues() {
  const result = [];
  for (const beat of board().beats.filter(b => !b.omitted && !unused(b))) {
    const causes = board().dependencies.filter(e => !e.reference && e.effect === beat.id).map(e => board().beats.find(b => b.id === e.cause)).filter(b => b && !b.omitted && !unused(b));
    if (beat.mustBeCaused && !causes.length) result.push({ id: beat.id, text: `${beat.title} needs a cause.` });
    if (causes.some(b => b.start + b.duration > beat.start + 0.00001)) result.push({ id: beat.id, text: `${beat.title} starts before its cause finishes.` });
  }
  try { causalOrder(); } catch (error) { result.push({ id: null, text: error.message }); } return result;
}
let boardZoom=1;
function boardPoint(event){const canvas=$('canvas'),frame=canvas.getBoundingClientRect();return {x:(event.clientX-frame.left+canvas.scrollLeft)/boardZoom,y:(event.clientY-frame.top+canvas.scrollTop)/boardZoom};}
function sizeBoardSurface(g=geometry()){
  $('board-world').style.width=g.width+'px';$('board-world').style.height=g.height+'px';$('board-world').style.transform=`scale(${boardZoom})`;
  $('board-extent').style.width=g.width*boardZoom+'px';$('board-extent').style.height=g.height*boardZoom+'px';$('board-zoom-reset').textContent=Math.round(boardZoom*100)+'%';
}
function zoomBoard(value,anchor=null){
  if(!doc)return;const canvas=$('canvas'),point=anchor??{x:canvas.clientWidth/2,y:canvas.clientHeight/2},world={x:(canvas.scrollLeft+point.x)/boardZoom,y:(canvas.scrollTop+point.y)/boardZoom};
  boardZoom=Math.max(.15,Math.min(3,value));sizeBoardSurface();canvas.scrollLeft=world.x*boardZoom-point.x;canvas.scrollTop=world.y*boardZoom-point.y;
}
$('board-zoom-in').onclick=()=>zoomBoard(boardZoom*1.25);$('board-zoom-out').onclick=()=>zoomBoard(boardZoom/1.25);$('board-zoom-reset').onclick=()=>zoomBoard(1);
$('canvas').addEventListener('wheel',e=>{if(!e.ctrlKey&&!e.metaKey)return;e.preventDefault();const frame=$('canvas').getBoundingClientRect();zoomBoard(boardZoom*Math.exp(-e.deltaY*.005),{x:e.clientX-frame.left,y:e.clientY-frame.top});},{passive:false});
$('canvas').addEventListener('keydown',e=>{if(e.target!==$('canvas')||!(e.ctrlKey||e.metaKey))return;if(['+','=','-','0'].includes(e.key)){e.preventDefault();zoomBoard(e.key==='0'?1:boardZoom*(e.key==='-'?.8:1.25));}});
function geometry() {
  const blocks = new Map(), beats = new Map(), layers = new Map(); let y = 0, maxX = 1500;
  for (const layer of board().layers) {
    const members = board().blocks.filter(b => b.layerID === layer.id), height = layer.collapsed ? 38 : Math.max(layer.height, ...members.map(b => b.position.y + board().beats.filter(t => t.blockID === b.id).reduce((h,t)=>h+beatSize(t.title,b.width-12).height+4,80)));
    layers.set(layer.id, { y, height });
    if (!layer.collapsed) for (const block of members) {
      let parent = board().blocks.find(b => b.id === block.parentID), hidden = false; const seen = new Set();
      while (parent && !seen.has(parent.id)) { if (parent.collapsed) hidden = true; seen.add(parent.id); parent = board().blocks.find(b => b.id === parent.parentID); }
      if (hidden) continue;
      const children = board().beats.filter(b => b.blockID === block.id).sort((a, b) => a.order - b.order);
      const rect = { x: block.position.x + 110, y: block.position.y + y, width: block.width, height: block.collapsed ? 28 : Math.max(layer.useBlocks===true&&!block.standalone&&block.containerKind!=='beatGroup'?180:60, children.reduce((h,b)=>h+beatSize(b.title,block.width-12).height+4,32)) };
      blocks.set(block.id, rect); maxX = Math.max(maxX, rect.x + rect.width + 120);
      if (!block.collapsed) { let top=rect.y+24;for(const beat of children){const size=beatSize(beat.title,block.width-12);beats.set(beat.id,{x:rect.x+(beat.position?.x??6),y:beat.position?rect.y+beat.position.y:top,...size});rect.width=Math.max(rect.width,(beat.position?.x??6)+size.width+12);rect.height=Math.max(rect.height,(beat.position?.y??top-rect.y)+size.height+12);top+=size.height+4;} }
    }
    const expanded=Math.max(height,...[...blocks.values()].filter(r=>r.y>=y).map(r=>r.y+r.height-y+45));layers.get(layer.id).height=expanded;
    y += expanded;
  }
  const byID = new Map(board().blocks.map(b => [b.id, b])), remaining = new Map([...blocks.keys()].map(id => [id, 0]));
  for (const block of board().blocks) if (blocks.has(block.id) && blocks.has(block.parentID)) remaining.set(block.parentID, remaining.get(block.parentID) + 1);
  const ready = [...remaining].filter(([, count]) => count === 0).map(([id]) => id);
  for (let i = 0; i < ready.length; i++) {
    const id = ready[i], parent = byID.get(id)?.parentID, c = blocks.get(id), r = blocks.get(parent);
    if (!c || !r || byID.get(parent).collapsed) continue;
    const left = Math.min(r.x, c.x - 12), top = Math.min(r.y, c.y - 28);
    blocks.set(parent, { x: left, y: top, width: Math.max(r.x + r.width, c.x + c.width + 12) - left, height: Math.max(r.y + r.height, c.y + c.height + 12) - top });
    remaining.set(parent, remaining.get(parent) - 1); if (!remaining.get(parent)) ready.push(parent);
  }
  maxX = Math.max(maxX, ...[...blocks.values()].map(r => r.x + r.width + 120), ...storyMarkers().map(m => 110 + m.unit * 120 + 200));
  return { blocks, beats, layers, width: maxX, height: Math.max(800, y) };
}
function position(node, rect) { node.style.left = `${rect.x}px`; node.style.top = `${rect.y}px`; node.style.width = `${rect.width}px`; node.style.height = `${rect.height}px`; }
function render() {
  const editingSide=document.activeElement?.hasAttribute('data-script-beat');
  if (!doc) return;
  if(filterProjectID!==current.id){filterProjectID=current.id;scriptFilter.clear();}
  const beatIDs = new Set(board().beats.map(b => b.id)), blockIDs = new Set(board().blocks.map(b => b.id));
  selectedBeats = new Set([...selectedBeats].filter(id => beatIDs.has(id))); selectedBlocks = new Set([...selectedBlocks].filter(id => blockIDs.has(id)));
  if (!beatIDs.has(selected)) selected = null;
  const g = geometry(), issues = storyIssues(), warning = new Set(issues.map(i => i.id));
  sizeBoardSurface(g);
  $('layers').replaceChildren(); $('blocks').replaceChildren(); $('links').replaceChildren(); if(!editingSide)$('snippet-list').replaceChildren(); $('issues').replaceChildren();
  for (const layer of board().layers) {
    const rect = g.layers.get(layer.id), node = element('div', undefined, 'layer'); position(node, { x: 0, y: rect.y, width: g.width, height: rect.height });
    const label = element('button', `${layer.collapsed ? '▸' : '▾'} ${layer.name}`, 'layer-label'); label.onclick = () => edit(() => { layer.collapsed = !layer.collapsed; }); node.append(label);const policy=element('button',usesBlocks(board(),layer.id)?'Blocks: On':layer.useBlocks==null&&board().blocks.some(b=>b.layerID===layer.id&&!b.standalone&&b.containerKind!=='beatGroup')?'Blocks: Legacy':'Blocks: Off','layer-block-policy');policy.setAttribute('aria-label',layer.name+' Use Blocks');policy.onclick=()=>edit(()=>{if(layer.locked)throw Error('Unlock the layer first.');layer.useBlocks=!usesBlocks(board(),layer.id);});node.append(policy); $('layers').append(node);
  }
  const blockOrder = [...board().blocks].sort((a, b) => { const x = g.blocks.get(a.id), y = g.blocks.get(b.id); return (y ? y.width * y.height : 0) - (x ? x.width * x.height : 0); });
  for (const block of blockOrder) {
    if(block.standalone&&!board().beats.some(b=>b.blockID===block.id)&&!board().blocks.some(b=>b.parentID===block.id))continue;
    const rect = g.blocks.get(block.id); if (!rect) continue;
    const node = element('div', undefined, `block${selectedBlocks.has(block.id) ? ' selected-block' : ''}`); node.dataset.blockId = block.id; position(node, rect);
    const loose = block.standalone && board().beats.filter(b => b.blockID === block.id).length === 1 && !board().blocks.some(b => b.parentID === block.id);
    node.classList.toggle('standalone', !!loose);node.classList.toggle('beat-group',block.containerKind==='beatGroup');node.dataset.containerKind=block.containerKind||'block';
    const title = element('div', block.name, 'block-title'); node.append(title);
    title.ondblclick = () => { const value = prompt('Block name', block.name); if (value !== null) edit(() => { block.name = value; }); };
    title.onpointerdown = e => {
      if (current.access === 'reader' || locked({ blockID: block.id })) return; e.preventDefault(); title.setPointerCapture(e.pointerId);
      if (e.shiftKey) { if (selectedBlocks.has(block.id)) selectedBlocks.delete(block.id); else selectedBlocks.add(block.id); }
      else if (!selectedBlocks.has(block.id)) selectedBlocks = new Set([block.id]);
      selectedBeats.clear();
      const moving = descendantBlocks(board(), selectedBlocks), start = { x: e.clientX, y: e.clientY };
      const nodes = [...$('blocks').children].filter(n => moving.has(n.dataset.blockId));
      title.onpointermove = event => { for (const item of nodes) { const r = g.blocks.get(item.dataset.blockId); item.style.left = `${r.x + (event.clientX - start.x)/boardZoom}px`; item.style.top = `${r.y + (event.clientY - start.y)/boardZoom}px`; } };
      title.onpointerup = event => {
        title.onpointermove = null; title.onpointerup = null;
        const frame=$('canvas').getBoundingClientRect(),y=boardPoint(event).y;
        const target=board().layers.find(l=>{const r=g.layers.get(l.id);return y>=r.y&&y<r.y+r.height;});
        if(selectedBlocks.size&&target&&Math.abs(event.clientX-start.x)+Math.abs(event.clientY-start.y)>3)edit(()=>{
          const x=boardPoint(event).x,dx=(event.clientX-start.x)/boardZoom,dy=(event.clientY-start.y)/boardZoom+g.layers.get(block.layerID).y-g.layers.get(target.id).y;
          const container=board().blocks.filter(b=>!moving.has(b.id)&&!b.standalone&&b.containerKind!=='beatGroup').filter(b=>{const r=g.blocks.get(b.id);return r&&x>=r.x&&x<=r.x+r.width&&y>=r.y&&y<=r.y+r.height;}).sort((a,b)=>{const r=g.blocks.get(a.id),s=g.blocks.get(b.id);return r.width*r.height-s.width*s.height;})[0];
          doc.project.frontstageWhiteboard=spatialOrder(container&&[...selectedBlocks].every(id=>board().blocks.find(b=>b.id===id)?.containerKind==='beatGroup')?nestGroups(board(),selectedBlocks,container.id,dx,dy):moveBlocks(board(),selectedBlocks,dx,dy,{layerID:target.id,ripple:$('ripple').checked}));
        });render();
      };
      title.onpointercancel = () => { title.onpointermove = null; title.onpointerup = null; render(); };
    };
    node.ondragover = e => e.preventDefault(); node.ondrop = e => {
      if(paletteDrop(e))return;
      e.preventDefault(); e.stopPropagation(); const id = e.dataTransfer.getData('text/frontstage-beat'), moving = board().beats.find(b => b.id === id); if (!moving || locked(moving) || locked({ blockID: block.id })) return;
      const targetBeat=e.target.closest('[data-beat-id]');
      if(block.standalone && (!targetBeat || moving.blockID === block.id)){dropStandaloneBeats(e);return;}
      if(targetBeat?.dataset.beatId===id)return;
      edit(() => { moving.blockID = block.id; moving.order = Math.max(-1, ...board().beats.filter(b => b.blockID === block.id && b.id !== id).map(b => b.order)) + 1;
        const hit=e.target.closest('[data-beat-id]');if(hit&&hit.dataset.beatId!==id){doc.project.frontstageWhiteboard=spatialOrder(dropBeats(board(),new Set([id]),hit.dataset.beatId));return;}if(!hit){const frame=node.getBoundingClientRect();moving.position={x:Math.max(6,(e.clientX-frame.left)/boardZoom),y:Math.max(24,(e.clientY-frame.top)/boardZoom)};}else delete moving.position; doc.project.frontstageWhiteboard=spatialOrder(pruneEmptyBeatContainers(board())); });
    };
    if (!block.collapsed) for (const beat of board().beats.filter(b => b.blockID === block.id).sort((a, b) => a.order - b.order)) {
      const tile = element('div', undefined, `beat${selectedBeats.has(beat.id) ? ' selected' : ''}`); tile.style.backgroundColor = beat.omitted ? '#777777' : /^#[a-f0-9]{6}$/i.test(beat.color) ? beat.color : '#a34eae';tile.classList.toggle('omitted',beat.omitted);tile.setAttribute('aria-label',beat.title+(beat.omitted?' · Omitted':''));
      tile.dataset.beatId = beat.id;
      const card=g.beats.get(beat.id);if(card){tile.style.position='absolute';position(tile,{...card,x:card.x-rect.x,y:card.y-rect.y});}
      tile.append(element('span', beat.title, 'beat-text')); tile.draggable = current.access !== 'reader' && !locked(beat);
      if (warning.has(beat.id)) tile.append(element('span', '!', 'badge'));
      tile.onclick = e => { e.stopPropagation(); choose(beat.id, e.shiftKey); }; tile.ondblclick = () => openEditor(beat.id);
      tile.ondragstart = e => {
        e.dataTransfer.setData('text/frontstage-beat', beat.id);
        const frame = node.getBoundingClientRect();
        e.dataTransfer.setData('text/frontstage-grab-offset', `${(e.clientX - frame.left)/boardZoom},${(e.clientY - frame.top)/boardZoom}`);
      };
      node.append(tile);
    }
    $('blocks').append(node);
  }
  $('links').setAttribute('width', g.width); $('links').setAttribute('height', g.height);
  for (const edge of board().dependencies) {
    const a = g.beats.get(edge.cause), b = g.beats.get(edge.effect); if (!a || !b) continue;
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path'), bend = Math.max(35, Math.abs(b.x - a.x - a.width) * .45);
    path.setAttribute('d', `M${a.x + a.width},${a.y + a.height / 2} C${a.x + a.width + bend},${a.y + a.height / 2} ${b.x - bend},${b.y + b.height / 2} ${b.x},${b.y + b.height / 2}`);
    path.setAttribute('stroke', edge.cause === selected || edge.effect === selected ? '#8be8f2' : '#d1d1d3'); path.setAttribute('fill', 'none'); if (edge.reference) path.setAttribute('stroke-dasharray', '4 4'); $('links').append(path);
  }
  for(const stroke of board().strokes||[])$('links').append(drawingPath(stroke.points,stroke.color,stroke.width));
  for (const marker of storyMarkers()) {
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'path'), x = 110 + marker.unit * 120;
    line.setAttribute('d', `M${x},0 V${g.height}`); line.setAttribute('stroke', '#4d8ed6'); line.setAttribute('stroke-dasharray', '3 5'); $('links').append(line);
  }
  renderReaderTools();
  renderSideSlugline();
  if(!editingSide)$('snippet-list').append(element('div',doc.name||'Untitled Story','script-project-title'));
  if(!editingSide&&selected){const beat=board().beats.find(b=>b.id===selected);if(beat&&!matchesScriptFilter(beat,board(),doc.project.beats,scriptFilter.state)){const notice=element('div','Selected beat is hidden by the current filters. ','script-filter-gap'),show=element('button','Reveal selected beat');show.onclick=()=>{scriptFilter.reset();render();document.querySelector(`[data-script-beat="${CSS.escape(selected)}"]`)?.scrollIntoView({block:'nearest'});};notice.append(show);$('snippet-list').append(notice);}}
  let filteredGap=[];
  if(!editingSide) for (const segment of scriptSegments(doc,{includeInactive:true})) {
    const visibleIDs=segment.beatIDs.filter(id=>matchesScriptFilter(board().beats.find(b=>b.id===id),board(),doc.project.beats,scriptFilter.state));
    if(!visibleIDs.length&&segment.beatIDs.length){filteredGap.push(...segment.beatIDs.map(id=>board().beats.find(b=>b.id===id)));continue;}
    const headingRow=element('h3',undefined,'script-heading');headingRow.append(element('span',heading(segment.scene)+(segment.continuation?' (CONTINUED)':'')),element('span',segment.number,'scene-number'));if(!scriptFilter.state.hideHeadings)$('snippet-list').append(headingRow);
    for(const id of segment.beatIDs){
      if(!visibleIDs.includes(id)){filteredGap.push(board().beats.find(b=>b.id===id));continue;}
      if(filteredGap.length&&!scriptFilter.state.hideGaps)$('snippet-list').append(element('div',gapLabel(filteredGap,scriptFilter.state.gaps),'script-filter-gap'));filteredGap=[];
      const beat=board().beats.find(b=>b.id===id),section=element('section',undefined,'script-beat-section'),title=element('button','▼ '+beat.title,'script-beat-title');
      section.classList.toggle('inactive-script-beat',!!beat.omitted||!!segment.scene.isDisabled||!!unused(beat));
      if(unused(beat)||beat.omitted||segment.scene.isDisabled)section.append(element('div',unused(beat)?'Unused lane · excluded from export':'Disabled beat · excluded from export','script-beat-status'));
      title.style.backgroundColor=beat.color+'22';title.ondblclick=()=>openEditor(id);
      const body=element('div',undefined,'script-beat-body');title.onclick=()=>{body.hidden=!body.hidden;title.textContent=(body.hidden?'▶ ':'▼ ')+beat.title;selected=id;selectedBeats=new Set([id]);highlightScript();};
      const plain=['Content Only','Final Script'].includes(reader.display);if(!plain)section.append(title);
      if(!plain&&((reader.characters&&beat.characters.length)||(reader.tags&&beat.tags.length)))section.append(metadataChips({...beat,characters:reader.characters?beat.characters:[],tags:reader.tags?beat.tags:[]}));
      if(!plain&&(reader.synopsis||reader.display==='Index Cards'))section.append(element('p',beat.synopsis,'reader-synopsis'));
      body.hidden=['Collapse All','Index Cards'].includes(reader.display);
      if(reader.boundaries&&!scriptFilter.state.hideBreaks){const owner=board().blocks.find(b=>b.id===beat.blockID);if(!owner.standalone&&board().beats.filter(b=>b.blockID===owner.id).sort((a,b)=>a.order-b.order)[0]?.id===id)$('snippet-list').append(element('div',owner.name,'reader-boundary'));}

      const text=element('div',undefined,'side-script-text script-text');text.innerHTML=cleanHTML(beat.html);text.dataset.scriptBeat=id;text.dataset.placeholder='Write this beat’s screenplay here…';text.tabIndex=0;text.setAttribute('aria-label',`Edit script: ${beat.title}`);text.contentEditable=current.access!=='reader'&&!segment.scene.frontstageTextLocked;text.setAttribute('role','textbox');
      text.onfocus=()=>{selected=id;selectedBeats=new Set([id]);highlightScript();document.querySelectorAll('[data-beat-id]').forEach(n=>n.classList.toggle('selected',n.dataset.beatId===id));};
      text.oninput=()=>edit(()=>{board().beats.find(b=>b.id===id).html=cleanHTML(text.innerHTML);});screenplayToolbar(text,()=>text.dispatchEvent(new Event('input')),text.contentEditable==='true',()=>characterNames(doc,id),()=>doc.project.beats.map(heading),{status,continuationSeed:()=>dialogueSeed(doc,id)});text.ondblclick=()=>openEditor(id);
      body.append(text);section.append(body);$('snippet-list').append(section);
    }
    if(!segment.beatIDs.length){const text=element('div',undefined,'script-text');text.innerHTML=cleanHTML(segment.html);$('snippet-list').append(text);}
  }
  for (const issue of issues) { const button = element('button', issue.text, 'issue'); button.onclick = () => { if (issue.id) choose(issue.id); }; $('issues').append(button); }
  $('beat-count').textContent = `${board().beats.length} beats`; renderProperties(); renderTimeline();
  document.querySelectorAll('.write').forEach(e => { e.disabled = current.access === 'reader'; });
  $('undo').disabled = current.access === 'reader' || !history.length; $('redo').disabled = current.access === 'reader' || !future.length;
  for (const [id, panel] of editors) {
    const beat = board().beats.find(b => b.id === id);
    if (!beat) { closeEditor(id); continue; }
    panel.querySelector('[data-field="snippet-editor"]').contentEditable = current.access === 'reader' || doc.project.beats.find(s => s.id === beat.sceneID)?.frontstageTextLocked ? 'false' : 'true';
  }  $('board-project-name').textContent = doc.name || 'Untitled Story';
  highlightScript();
  refreshEditors();
  workspaces.render();
}
function renderReaderTools() {
  const root=$('reader-tools');if(root.childElementCount)return;
  const menu=(name)=>{const d=element('details'),summary=element('summary',name);d.append(summary);root.append(d);const body=element('div',undefined,'reader-menu');d.append(body);return body;};
  const action=(parent,label,run)=>{const b=element('button',label);b.onclick=()=>{run();parent.closest('details').open=false;applyReader();render();};parent.append(b);};
  const display=menu('Display');for(const mode of ['Expand All','Index Cards','Collapse All','Content Only','Final Script'])action(display,mode,()=>reader.display=mode);
  for(const [key,label]of [['characters','Show Characters'],['tags','Show Tags'],['synopsis','Show Synopsis Field'],['boundaries','Show Block/Group Beginnings']]){const labelNode=element('label',label),input=element('input');input.type='checkbox';input.checked=reader[key];input.onchange=()=>{reader[key]=input.checked;render();};labelNode.prepend(input);display.append(labelNode);}
  for(const mode of ['Full Margins','Compact Margins','Squeezed','Super Squeezed'])action(display,mode,()=>reader.margin=mode);
  const styling=menu('Styling');action(styling,'Zoom In',()=>reader.zoom=Math.min(2,reader.zoom+.1));action(styling,'Zoom Out',()=>reader.zoom=Math.max(.7,reader.zoom-.1));action(styling,'100%',()=>reader.zoom=1);
  const filter=menu('Filter');mountScriptFilter(filter,scriptFilter,{board,scenes:()=>doc.project.beats,selection:()=>selectedBeats.size?selectedBeats:new Set(board().beats.filter(b=>descendantBlocks(board(),selectedBlocks).has(b.blockID)).map(b=>b.id)),changed:()=>render()});
  const presets=menu('Presets');for(const [label,mode]of [['Reading','Final Script'],['Story Review','Expand All'],['Index Cards','Index Cards']])action(presets,label,()=>reader.display=mode);
  const options=menu('Options');action(options,'Follow Selected Beat',()=>reader.follow=!reader.follow);action(options,'Full Screen',()=>{if(document.fullscreenElement)document.exitFullscreen();else document.documentElement.requestFullscreen().catch(()=>{});});
  applyReader();
}
function applyReader(){const inset={'Full Margins':48,'Compact Margins':16,'Squeezed':8,'Super Squeezed':3}[reader.margin];$('script').style.setProperty('--reader-inset',inset+'px');$('script').style.setProperty('--reader-font',(14*reader.zoom)+'px');}
function renderSideSlugline() { $('side-slugline')?.remove(); }
function characterColor(name) { const palette=['#11106b','#5de5bb','#a30e3f','#d6ae1c','#467e96'];return palette[[...name].reduce((sum,c)=>sum+c.codePointAt(0),0)%palette.length]; }
function metadataChips(beat, removable=false, update=null) {
  const root=element('div',undefined,'beat-chips');
  for(const name of beat.characters){const chip=element('span',undefined,'character-chip'),dot=element('i');dot.style.backgroundColor=characterColor(name);chip.append(dot,document.createTextNode(name));root.append(chip);}
  for(const tag of beat.tags){const chip=element(removable?'button':'span',`${removable?'× ':''}${tag}`,'tag-chip');if(removable)chip.onclick=()=>update(tag);root.append(chip);}
  return root;
}
function highlightScript(scroll = false) {
  renderSideSlugline();
  for(const toolbar of $('snippet-list').querySelectorAll('[data-script-toolbar]'))toolbar.hidden=toolbar.dataset.scriptToolbar!==selected;
  for (const text of $('snippet-list').querySelectorAll('[data-script-beat]')) {
    const active = text.dataset.scriptBeat === selected;
    text.classList.toggle('active-script-beat', active);
    if (active) text.setAttribute('aria-current','true'); else text.removeAttribute('aria-current');
    if (active && scroll && reader.follow && !$('script').hidden) { text.closest('.script-beat-body').hidden=false; text.scrollIntoView({block:'start'}); }
  }
}
function renderProperties() {
  const beat = board().beats.find(b => b.id === selected), target = $('beat-properties'); target.replaceChildren(); if (!beat) { target.textContent = 'Select a beat. Double-click to edit its snippet.'; return; }
  for (const [label, key] of [['Name', 'title'], ['Synopsis', 'synopsis'], ['Start', 'start'], ['Duration', 'duration']]) {
    const wrapper = element('label', label), input = element('input'); input.value = beat[key]; input.disabled = current.access === 'reader';
    input.onchange = () => edit(() => { if (key === 'start' || key === 'duration') { const n = Number(input.value); if (!Number.isFinite(n) || n < (key === 'duration' ? .05 : 0)) throw Error('Invalid story time'); beat[key] = n; } else beat[key] = input.value; }); wrapper.append(input); target.append(wrapper);
  }
  const open = element('button', 'Open Popup Editor'); open.onclick = () => openEditor(beat.id); target.append(open);
  for (const [title, key] of [['Must Be Caused', 'mustBeCaused'], ['Omitted', 'omitted'], ['Locked', 'locked']]) {
    const label = element('label', title), input = element('input'); input.type = 'checkbox'; input.checked = beat[key]; input.disabled = current.access === 'reader'; input.onchange = () => edit(() => { beat[key] = input.checked; }); label.prepend(input); target.append(label);
  }
  const color = element('input'); color.type = 'color'; color.value = /^#[a-f0-9]{6}$/i.test(beat.color) ? beat.color : '#a34eae'; color.disabled = current.access === 'reader'; color.onchange = () => edit(() => { beat.color = color.value; }); target.append(color);
  for (const edge of board().dependencies.filter(e => e.cause === beat.id || e.effect === beat.id)) {
    const other = board().beats.find(b => b.id === (edge.cause === beat.id ? edge.effect : edge.cause)); const row = element('p', `${edge.cause === beat.id ? '→' : '←'} ${other?.title || 'Beat'}`);
    const remove = element('button', 'Remove'); remove.disabled = current.access === 'reader'; remove.onclick = () => edit(() => { board().dependencies = board().dependencies.filter(e => e.id !== edge.id); }); row.append(remove); target.append(row);
  }
}
function detachTimeline(){
  if(timelineWindow&&!timelineWindow.closed){timelineWindow.focus();return;}
  const target=window.open('about:blank','frontstage-timeline','popup,width=1200,height=720');
  if(!target){status('Allow popups for DOT to open the timeline window.');return;}
  saveTimelinePreferences();Object.assign(timelineState,loadTimelinePreferences(true),{expanded:true,lastSelected:null});
  timelineWindow=target;target.document.title='DOT · Timeline · '+doc.name;
  for(const sheet of document.querySelectorAll('link[rel="stylesheet"]')){const link=target.document.createElement('link');link.rel='stylesheet';link.href=sheet.href;target.document.head.append(link);}
  const style=target.document.createElement('style');style.textContent='html,body{margin:0;height:100%;display:block!important}#detached-timeline{height:100vh!important;width:100vw;display:flex;flex-direction:column}.story-timeline-scroll{flex:1}';target.document.head.append(style);
  timelineWindowRoot=target.document.createElement('div');timelineWindowRoot.id='detached-timeline';target.document.body.append(timelineWindowRoot);
  target.addEventListener('beforeunload',()=>{timelineWindow=null;timelineWindowRoot=null;saveTimelinePreferences();Object.assign(timelineState,loadTimelinePreferences(false),{expanded:false,lastSelected:null});renderTimeline();},{once:true});
  renderTimeline();
}
window.addEventListener('beforeunload',()=>timelineWindow?.close());
function renderTimeline() {
  saveTimelinePreferences();
  $('board-area').classList.toggle('timeline-expanded',timelineState.expanded&&!timelineWindowRoot);$('workspace').classList.toggle('timeline-focus',timelineState.expanded&&!timelineWindowRoot);$('timeline').style.display=timelineWindowRoot?'none':'';
  mountTimeline(timelineWindowRoot??$('timeline'),timelineModel(board(),doc.project.beats,storyMarkers(),timelineState.timeBase,doc.project.frontstageTimelineOptions?.minutesPerPage,doc.project.frontstageTimelineOptions?.trackGroups),timelineState,{
    selected,choose,open:openEditor,render:renderTimeline,detached:!!timelineWindowRoot,detach:detachTimeline,dock:()=>timelineWindow?.close(),
    group:(kind,name,previous)=>{if(current.access==='reader')return;const group=prompt(kind==='tags'?'Tag category':'Character group',previous);if(group===null)return;edit(()=>{if(!group.trim()||group.trim().length>120)throw Error('Choose a name between 1 and 120 characters.');doc.project.frontstageTimelineOptions??={};doc.project.frontstageTimelineOptions.trackGroups??={};doc.project.frontstageTimelineOptions.trackGroups[kind]??={};doc.project.frontstageTimelineOptions.trackGroups[kind][name]=group.trim();});},
    expand:expanded=>{saveTimelinePreferences();Object.assign(timelineState,loadTimelinePreferences(expanded),{expanded,lastSelected:null});renderTimeline();},
    addMarker:type=>editMarker(null,type),
    markerType:id=>{if(current.access==='reader')return;const marker=storyMarkers().find(m=>m.id===id);if(!marker)return;const type=prompt('Break type: episode, act, chapter, section',marker.type==='custom'?'act':marker.type??'act');if(type===null)return;edit(()=>{if(!['episode','act','chapter','section'].includes(type))throw Error('Choose episode, act, chapter or section.');doc.project.sectionBreaks.find(m=>m.id===id).type=type;});},
    timing:()=>{if(current.access==='reader')return;const raw=prompt('Estimated minutes per screenplay page (0.1–10). Explicit beat durations stay unchanged.',String(doc.project.frontstageTimelineOptions?.minutesPerPage??1));if(raw===null)return;edit(()=>{const value=Number(raw);if(!Number.isFinite(value)||value<.1||value>10)throw Error('Choose 0.1 to 10 minutes per page.');doc.project.frontstageTimelineOptions??={};doc.project.frontstageTimelineOptions.minutesPerPage=value;});},
    reorder:(ids,target)=>edit(()=>{doc.project.frontstageWhiteboard=reorderTimelineBeats(board(),new Set(ids),target);}),
    moveMarker:(id,unit)=>edit(()=>{const marker=doc.project.sectionBreaks.find(m=>m.id===id);if(marker)marker.unit=Math.max(0,unit);}),
    marker:id=>editMarker(storyMarkers().find(m=>m.id===id)),
    duration:id=>{if(current.access==='reader')return;const b=board().beats.find(b=>b.id===id);if(!b||locked(b))return;const raw=prompt('Duration override in minutes (blank = estimate from screenplay)',b.timelineDuration??'');if(raw===null)return;edit(()=>{const value=Number(raw);if(raw.trim()&&(!Number.isFinite(value)||value<=0||value>1000))throw Error('Use a duration between 0 and 1000 minutes.');if(raw.trim())b.timelineDuration=value;else delete b.timelineDuration;});},
    emotion:(id,tag)=>{if(current.access==='reader')return;const b=board().beats.find(b=>b.id===id);if(!b||locked(b))return;const raw=prompt('Emotion change (-100 to 100); prefix = for an absolute 0–100 checkpoint',String(b.emotionChanges?.[tag]??0));if(raw===null)return;const tension=prompt('Momentary beat tension (-5 to +5)',String(b.tensions?.[tag]??0));if(tension===null)return;edit(()=>{const absolute=raw.startsWith('='),value=Number(absolute?raw.slice(1):raw),t=Number(tension);if(!Number.isFinite(value)||value<(absolute?0:-100)||value>100||!Number.isFinite(t)||Math.abs(t)>5)throw Error('Emotion and tension values are outside their allowed range.');b.emotionChanges??={};b.emotionChanges[tag]=value;b.emotionAbsoluteTags=(b.emotionAbsoluteTags??[]).filter(x=>x!==tag);if(absolute)b.emotionAbsoluteTags.push(tag);b.tensions??={};b.tensions[tag]=t;});}
  });
}

function storyMarkers() {
  const seen = new Set();
  return (Array.isArray(doc.project.sectionBreaks) ? doc.project.sectionBreaks : []).filter(m => m && typeof m.id === 'string' && Number.isFinite(m.unit) && m.unit >= 0 && m.unit <= 1000000 / 120 && !seen.has(m.id) && seen.add(m.id)).sort((a, b) => a.unit - b.unit || a.id.localeCompare(b.id));
}
function editMarker(marker = null, kind = 'act') {
  if (current.access === 'reader') return;
  const title = prompt('Structural break name', marker?.title || `${kind[0].toUpperCase()+kind.slice(1)} ${storyMarkers().length + 1}`); if (!title?.trim()) return;
  const raw = prompt('Estimated story time', String(marker?.unit ?? board().beats.find(b => b.id === selected)?.start ?? 0)); if (raw === null) return;
  const unit = Number(raw);
  edit(() => {
    if (!Number.isFinite(unit) || unit < 0 || unit > 1000000 / 120) throw Error('Choose a valid estimated story time.');
    if (doc.project.sectionBreaks !== undefined && !Array.isArray(doc.project.sectionBreaks)) throw Error('Existing marker data has an unsupported format.');
    doc.project.sectionBreaks ||= [];
    if (marker) { const stored = doc.project.sectionBreaks.find(m => m.id === marker.id); if (stored) { stored.title = title; stored.unit = unit; } }
    else doc.project.sectionBreaks.push({ id: uuid(), title, unit, type: kind });
  });
}
const editors = new Map();
let editorStack = 20;
const editorFields = [['beat-title', 'title'], ['beat-synopsis', 'synopsis'], ['beat-kind', 'kind'], ['must-cause', 'mustBeCaused'], ['beat-characters', 'characters'], ['beat-tags', 'tags']];
function refreshEditors(force = false) {
  for (const [id, panel] of editors) {
    const beat = board().beats.find(b => b.id === id);
    if (!beat) { closeEditor(id); continue; }
    for (const [name, key] of editorFields) {
      const input = panel.querySelector(`[data-field="${name}"]`);
      if (!force && document.activeElement === input) continue;
      if (key === 'mustBeCaused') input.checked = beat[key];
      else { const value = Array.isArray(beat[key]) ? beat[key].join(', ') : (beat[key] ?? ''); if (input.value !== value) input.value = value; }
    }
    panel.querySelector('[data-field="beat-visibility"]').value=beat.omitted?'hidden':'visible';
    panel.querySelector('[data-field="beat-used"]').textContent=unused(beat)?'Beat is unused':'✓ Beat is used';
    panel.querySelector('[data-field="character-chips"]').replaceChildren(metadataChips({...beat,tags:[]}));
    panel.querySelector('[data-field="tag-chips"]').replaceChildren(metadataChips({...beat,characters:[]},current.access!=='reader',tag=>edit(()=>{board().beats.find(b=>b.id===id).tags=beat.tags.filter(t=>t!==tag);})));
    const version=panel.querySelector('[data-field="beat-version"]'),scene=doc.project.beats.find(s=>s.id===beat.sceneID);
    if(document.activeElement!==version){version.replaceChildren(new Option('Untitled Version (current)',''));for(const v of scene?.versions||[])version.append(new Option(v.frontstageLabel||v.title||'Version',v.id));}
    panel.querySelector('.slugline-fields')?.refresh();
    const isReadOnly=current.access==='reader'||!!doc.project.beats.find(s=>s.id===beat.sceneID)?.frontstageTextLocked;
    panel.querySelectorAll('.screenplay-toolbar select,.screenplay-toolbar button').forEach(control=>control.disabled=isReadOnly);
    const headingNode=panel.querySelector('.popup-slugline');if(headingNode)headingNode.textContent=heading(doc.project.beats.find(s=>s.id===beat.sceneID));
    const text = panel.querySelector('[data-field="snippet-editor"]'), html = cleanHTML(beat.html);
    if (cleanHTML(text.innerHTML) !== html) text.innerHTML = html;
    text.refreshScreenplayPresentation?.();
  }
}
function closeEditors() { for (const id of [...editors.keys()]) closeEditor(id); }
function closeEditor(id) {
  const hadFocus = editors.get(id)?.contains(document.activeElement), wasActive = editorID === id;
  editors.get(id)?.remove(); editors.delete(id);
  if (wasActive) {
    editorID = [...editors.keys()].sort((a, b) => Number(editors.get(a).style.zIndex) - Number(editors.get(b).style.zIndex)).at(-1) || null;
    if (editorID) { activateEditor(editorID); if (hadFocus) editors.get(editorID).querySelector('[data-field="snippet-editor"]').focus(); }
    else if (hadFocus) $('canvas').focus();
  }
}
function activateEditor(id) {
  editorID = id;
  for (const [key, panel] of editors) panel.classList.toggle('active', key === id);
  editors.get(id).style.zIndex = ++editorStack;
}
function openEditor(id) {
  const beat = board().beats.find(b => b.id === id); if (!beat) return;
  if (editors.has(id)) { activateEditor(id); const name = !beat.title.trim() || beat.title === 'Untitled Beat'; editors.get(id).querySelector(name ? '[data-field="beat-title"]' : '[data-field="snippet-editor"]').focus(); return; }
  const panel = $('editor').cloneNode(true); panel.hidden = false;
  panel.classList.add('beat-popup'); panel.dataset.beatId = id;
  for (const field of [panel, ...panel.querySelectorAll('[id]')]) { field.dataset.field = field.id; field.id = `${id}-${field.id}`; }
  panel.setAttribute('aria-labelledby', `${id}-editor-label`);
  const field = name => panel.querySelector(`[data-field="${name}"]`);
  editors.set(id, panel); document.body.append(panel); activateEditor(id); selected = id;
  panel.addEventListener('pointerdown', () => activateEditor(id));
  panel.addEventListener('focusin', () => activateEditor(id));
  field('close-editor').onclick = () => closeEditor(id);
  for (const [name, key] of editorFields) {
    const input = field(name);
    if (key === 'mustBeCaused') input.checked = beat[key]; else { const value = Array.isArray(beat[key]) ? beat[key].join(', ') : (beat[key] ?? ''); if (input.value !== value) input.value = value; }
    input.disabled = current.access === 'reader';
    input.oninput = () => edit(() => { const target = board().beats.find(b => b.id === id); if (target) target[key] = key === 'mustBeCaused' ? input.checked : ['characters', 'tags'].includes(key) ? list(input.value) : input.value; });
  }
  field('close-bottom').onclick=()=>closeEditor(id);
  field('beat-visibility').onchange=()=>edit(()=>{board().beats.find(b=>b.id===id).omitted=field('beat-visibility').value==='hidden';});
  field('script-section-toggle').onclick=()=>{const section=panel.querySelector('.popup-script-section');section.hidden=!section.hidden;field('script-section-toggle').textContent=(section.hidden?'▶':'▼')+' Script';field('script-section-toggle').setAttribute('aria-expanded',String(!section.hidden));};
  for(const key of ['character','tag'])field('add-'+key).onclick=()=>field(key==='character'?'beat-characters':'beat-tags').focus();
  field('version-save').onclick=()=>{const label=prompt('Version name');if(label)edit(()=>captureRevision(doc,beat.sceneID,label));};
  field('beat-version').onchange=()=>{const version=field('beat-version').value;if(version)edit(()=>restoreRevision(doc,beat.sceneID,version));};
  const sceneID=beat.sceneID;
  const controls=sluglineFields(()=>doc.project.beats.find(s=>s.id===sceneID),()=>doc.project.beats,edit,current.access!=='reader');
  panel.querySelector('.paper-desk').before(controls);
  const text = field('snippet-editor');text.classList.add('script-text');const typography=popupTypography(doc.project.frontstageScriptLayout);applyTypography(text,typography);text.style.fontFamily=JSON.stringify(typography.fontName)+',monospace';text.style.fontSize=typography.fontSize+'px';text.style.lineHeight=typography.lineHeight+'px'; text.before(element('h3',heading(doc.project.beats.find(s=>s.id===sceneID)),'popup-slugline script-heading')); text.innerHTML = cleanHTML(beat.html);
  text.contentEditable = current.access === 'reader' || doc.project.beats.find(s => s.id === beat.sceneID)?.frontstageTextLocked ? 'false' : 'true';
  text.oninput = () => { const html = cleanHTML(text.innerHTML); edit(() => { const target = board().beats.find(b => b.id === id); if (target) target.html = html; }); };
  const toolbar=screenplayToolbar(text, () => text.dispatchEvent(new Event('input')), text.contentEditable === 'true',()=>characterNames(doc,id),()=>doc.project.beats.map(heading),{status,continuationSeed:()=>dialogueSeed(doc,id),newScene:node=>{
    const parts=[...text.children],index=parts.indexOf(node);if(index<0)return;
    let next;const first=parts.slice(0,index+1).map(n=>cleanHTML(n.outerHTML)).join(''),second=parts.slice(index+1).map(n=>cleanHTML(n.outerHTML)).join('');
    const ordered=[...board().beats].sort((a,b)=>a.order-b.order),rank=ordered.findIndex(b=>b.id===id),following=ordered[rank+1],nextScene=doc.project.beats.find(s=>s.id===following?.sceneID);
    if(!second&&following&&!locked(following)&&!following.omitted&&!unused(following)&&nextScene&&!nextScene.frontstageTextLocked&&following.sceneID!==beat.sceneID&&['prefix','location','time'].every(key=>!nextScene.slug?.[key]?.trim())){openEditor(following.id);editors.get(following.id)?.querySelector('[data-slug-key="location"]')?.focus();return;}
    if(edit(()=>{next=insertScriptScene(doc,id,first,second,'');})){openEditor(next);const nextPanel=editors.get(next);nextPanel?.querySelector('[data-slug-key="location"]')?.focus();}
  }});field('element').parentElement.replaceWith(toolbar);panel.querySelector('.version-row').append(toolbar);const options=element('button','⋯');options.setAttribute('aria-label','Formatting options');options.onclick=()=>panel.classList.toggle('format-expanded');panel.querySelector('.version-row').append(options);refreshEditors();
  const place = (x, y) => {
    const rect = panel.getBoundingClientRect();
    panel.style.left = `${Math.max(8, Math.min(x, innerWidth - rect.width - 8))}px`;
    panel.style.top = `${Math.max(60, Math.min(y, innerHeight - rect.height - 36))}px`;
  };
  const tile = [...$('blocks').querySelectorAll('[data-beat-id]')].find(node => node.dataset.beatId === id);
  tile?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  const rect = tile?.getBoundingClientRect(); place((rect?.right || 120) + 12 + editors.size * 24, (rect?.top || 80) - 25 + editors.size * 24);
  panel.querySelector('.editor-header').onpointerdown = event => {
    if (event.target.closest('button, input, select, textarea')) return;
    event.preventDefault(); const header = event.currentTarget, frame = panel.getBoundingClientRect(), x = event.clientX, y = event.clientY;
    header.setPointerCapture(event.pointerId);
    header.onpointermove = e => place(frame.left + e.clientX - x, frame.top + e.clientY - y);
    header.onpointerup = header.onpointercancel = () => { header.onpointermove = null; header.onpointerup = null; header.onpointercancel = null; };
  };
  field('split-beat').onpointerdown = e => e.preventDefault();
  field('split-beat').onclick = () => { try { const [first, second] = splitAtCaret(text); let next; edit(() => { next = splitBeat(doc, id, cleanHTML(first), cleanHTML(second)); }); if (next && board().beats.some(b => b.id === next)) { refreshEditors(); openEditor(next); } } catch (e) { status(e.message); } };
  field(!beat.title.trim() || beat.title === 'Untitled Beat' ? 'beat-title' : 'snippet-editor').focus();
}
function addBeat(standalone = false, afterID = null, asGroup = false) {
  edit(() => {
    const previous=board().beats.find(b=>b.id===afterID),previousBlock=board().blocks.find(b=>b.id===previous?.blockID);const owner = standalone ? null : board().beats.find(b => b.id === selected); let blockID = owner?.blockID, sceneID = isSceneModel(doc)?null:previous?.sceneID??owner?.sceneID;
    if(isSceneModel(doc)){sceneID=Math.max(0,...doc.project.beats.map(s=>s.id))+1;doc.project.beats.push({id:sceneID,title:'Untitled Beat',summary:'',content:'',slug:{prefix:'INT.',location:'',time:'DAY'}});doc.project.nextId=sceneID+1;}
    if((owner&&locked(owner))||(previous&&locked(previous)))throw Error('Unlock the destination before adding a beat.');
    if (!blockID) {
      blockID = uuid(); if(sceneID==null){ sceneID = Math.max(0, ...doc.project.beats.map(b => Number(b.id))) + 1;
      doc.project.beats.push({ id: sceneID, title: 'Untitled Scene', content: '', slug: { prefix: 'INT.', location: '', time: 'DAY' }, boardId: 0 }); doc.project.nextId = sceneID + 1; }
      const right = Math.max(-244, ...board().blocks.map(b => b.position.x + b.width));
      board().blocks.push({ standalone, id: blockID, name: asGroup?'Beat Group':'Untitled Block', ...(asGroup?{containerKind:'beatGroup'}:{}), layerID: previousBlock?.layerID??board().layers[0].id, position: previousBlock ? {x:previousBlock.position.x,y:previousBlock.position.y+beatSize(previous.title,previousBlock.width-12).height+12} : { x: Math.max(40, right + 60), y: 70 }, width: 224, collapsed: false, locked: false });
    }
    const destination=board().blocks.find(b=>b.id===blockID);if(owner&&destination.standalone){destination.standalone=false;destination.containerKind='beatGroup';destination.name='Beat Group';}
    const beat = { id: uuid(), sceneID, blockID, title: 'Untitled Beat', synopsis: '', html: '', kind: 'story', color: '#a34eae', characters: [], tags: [], mustBeCaused: false, omitted: false, locked: false, order: Math.max(-1, ...board().beats.map(b => b.order)) + 1, start: Math.max(0, ...board().beats.map(b => b.start + b.duration)), duration: 1.5 };
    if(previous){const ordered=[...board().beats].sort((a,b)=>a.order-b.order),index=ordered.findIndex(b=>b.id===previous.id);beat.order=(previous.order+(ordered[index+1]?.order??previous.order+2))/2;}
    board().beats.push(beat); selected = beat.id; selectedBeats=new Set([beat.id]);
  }); openEditor(selected);
}
$('canvas').ondragover = e => e.preventDefault();
$('canvas').ondrop = dropStandaloneBeats;
function dropStandaloneBeats(e) {
  if(paletteDrop(e))return;
  e.preventDefault();
  const id = e.dataTransfer.getData('text/frontstage-beat'), beat = board().beats.find(b => b.id === id);
  const block = board().blocks.find(b => b.id === beat?.blockID);
  if (!beat || !block || locked(beat)) return;
  const frame = $('canvas').getBoundingClientRect(), rect = geometry().blocks.get(block.id);
  if (!rect) return;
  const offset = e.dataTransfer.getData('text/frontstage-grab-offset').split(',').map(Number);
  const [ox, oy] = offset.length === 2 && offset.every(Number.isFinite) ? offset : [0, 0];
  const ids = selectedBeats.has(id) ? selectedBeats : new Set([id]);
  const g = geometry(), x=boardPoint(e).x, y=boardPoint(e).y;
  const target=board().layers.find(l=>{const r=g.layers.get(l.id);return y>=r.y&&y<r.y+r.height;});
  if (!target) return;
  edit(() => {
    if ([...ids].every(id=>{const b=board().beats.find(b=>b.id===id);return board().blocks.find(x=>x.id===b?.blockID)?.standalone;})) {
      doc.project.frontstageWhiteboard=moveStandaloneBeats(board(),ids,x-rect.x-ox,y-rect.y-oy+g.layers.get(block.layerID).y-g.layers.get(target.id).y,{layerID:target.id,ripple:$('ripple').checked});
    } else doc.project.frontstageWhiteboard=moveBeatsToLayer(board(),ids,target.id,{x:x-110,y:y-g.layers.get(target.id).y});
    doc.project.frontstageWhiteboard=spatialOrder(board());
  });
}
function createPalette(kind,layerID,position,parentID=null,inlineTitle=null){
  let created=null;edit(()=>{
    const layer=board().layers.find(l=>l.id===layerID);if(!layer||layer.locked)throw Error('Unlock the destination layer.');
    if(kind==='lane'){const index=board().layers.indexOf(layer);board().layers.splice(index+1,0,{id:uuid(),name:'New Layer',height:300,collapsed:false,locked:false,unused:false,useBlocks:false});return;}
    const parent=board().blocks.find(b=>b.id===parentID);
    if(parent&&(parent.layerID!==layerID||parent.standalone||locked({blockID:parentID})))throw Error('Choose an unlocked block or group.');
    if(kind==='block'&&!usesBlocks(board(),layerID))throw Error('Enable Use Blocks on this layer before adding a block.');
    if(kind!=='block'&&usesBlocks(board(),layerID)&&!parent)throw Error('Drop inside a block on this layer.');
    if(kind!=='beat'){board().blocks.push({id:uuid(),name:kind==='group'?'Beat Group':'Untitled Block',...(kind==='group'?{containerKind:'beatGroup'}:{}),...(parent?{parentID:parent.id}:{}),layerID,position,width:kind==='block'?500:224,collapsed:false,locked:false});return;}
    let blockID=parent?.id;if(!blockID){blockID=uuid();board().blocks.push({id:blockID,name:'Beat',standalone:true,layerID,position,width:224,collapsed:false,locked:false});}
    const sceneID=Math.max(0,...doc.project.beats.map(b=>Number(b.id)))+1;doc.project.beats.push({id:sceneID,title:'Untitled Scene',content:'',slug:{prefix:'INT.',location:'',time:'DAY'},boardId:0});doc.project.nextId=sceneID+1;
    created=uuid();board().beats.push({id:created,sceneID,blockID,title:inlineTitle??'Untitled Beat',synopsis:'',html:'',kind:'story',color:'#a34eae',characters:[],tags:[],mustBeCaused:false,omitted:false,locked:false,order:Math.max(-1,...board().beats.map(b=>b.order))+1,start:Math.max(0,...board().beats.map(b=>b.start+b.duration)),duration:1.5,...(parent?{position:{x:Math.max(6,position.x-parent.position.x),y:Math.max(24,position.y-parent.position.y)}}:{})});selected=created;selectedBeats=new Set([created]);
  });if(created&&board().beats.some(b=>b.id===created)){if(inlineTitle===null)openEditor(created);return created;}return null;
}
function paletteDrop(e){
  const kind=e.dataTransfer?.getData('text/frontstage-create');if(!['lane','block','group','beat'].includes(kind))return false;
  e.preventDefault();e.stopPropagation();const frame=$('canvas').getBoundingClientRect(),g=geometry(),x=boardPoint(e).x,y=boardPoint(e).y;
  const layer=board().layers.find(l=>{const r=g.layers.get(l.id);return y>=r.y&&y<r.y+r.height;});if(!layer)return true;
  const parent=board().blocks.find(b=>b.id===e.target.closest('[data-block-id]')?.dataset.blockId&&!b.standalone);
  createPalette(kind,layer.id,{x:Math.max(0,x-110),y:Math.max(32,y-g.layers.get(layer.id).y)},['block','lane'].includes(kind)?null:parent?.id);return true;
}
for(const [id,kind]of [['add-layer','lane'],['add-block','block'],['add-group','group'],['add-beat','beat']]){const button=$(id);button.draggable=true;button.title='Drag onto the whiteboard to create a '+kind;button.ondragstart=e=>{if(current.access==='reader'){e.preventDefault();return;}e.dataTransfer.setData('text/frontstage-create',kind);e.dataTransfer.effectAllowed='copy';};}
let inlineBeatInput=null;
function beginInlineBeat(layerID,position,parentID=null){
  inlineBeatInput?.remove();inlineBeatInput=null;
  const layer=board().layers.find(l=>l.id===layerID);
  if(current.access==='reader'||!layer||layer.locked)return;
  if(usesBlocks(board(),layerID)&&!parentID){status('Create beats inside a block on this layer.');return;}
  if(parentID&&locked({blockID:parentID}))return;
  const input=element('input',undefined,'inline-beat-name');input.placeholder='Beat name';input.setAttribute('aria-label','New beat name');
  input.style.left=(position.x+110)+'px';input.style.top=(position.y+geometry().layers.get(layerID).y)+'px';
  $('board-world').append(input);inlineBeatInput=input;input.focus();
  let finished=false;
  const finish=next=>{if(finished)return;finished=true;const title=input.value.trim();input.remove();inlineBeatInput=null;
    if(title){const id=createPalette('beat',layerID,position,parentID,title);if(id&&next){const rect=geometry().beats.get(id);beginInlineBeat(layerID,{x:position.x,y:position.y+(rect?.height??28)+12},parentID);}}
  };
  input.onkeydown=e=>{if(e.isComposing)return;if(e.key==='Enter'){e.preventDefault();e.stopPropagation();finish(true);}if(e.key==='Escape'){e.preventDefault();e.stopPropagation();finished=true;input.remove();inlineBeatInput=null;$('canvas').focus();}};
  input.onblur=()=>finish(false);
  input.ondblclick=e=>e.stopPropagation();
}
let drawingTool='select';
function drawingPath(points,color='#ffd54a',width=2){const path=document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d',points.map((p,i)=>`${i?'L':'M'}${p.x},${p.y}`).join(' '));path.setAttribute('stroke',color);path.setAttribute('stroke-width',width);path.setAttribute('stroke-linecap','round');path.setAttribute('stroke-linejoin','round');path.setAttribute('fill','none');return path;}
const drawingButtons=[];
for(const [tool,label]of [['select','Select'],['draw','Draw'],['erase','Eraser']]){const button=element('button',label);button.dataset.boardTool=tool;button.setAttribute('aria-pressed',String(tool==='select'));button.onclick=()=>{drawingTool=tool;for(const item of drawingButtons)item.setAttribute('aria-pressed',String(item.dataset.boardTool===tool));};drawingButtons.push(button);}
$('fit').after(...drawingButtons);
$('canvas').addEventListener('pointerdown',event=>{
 const pan=event.button===1;
 if(!pan&&(event.button!==0||drawingTool==='select'||event.target.closest('input,button,textarea')))return;
 if(!pan&&current.access==='reader')return;
 event.preventDefault();event.stopImmediatePropagation();
 const canvas=$('canvas'),start={x:event.clientX,y:event.clientY,left:canvas.scrollLeft,top:canvas.scrollTop},points=[boardPoint(event)],preview=pan?null:drawingPath(points,drawingTool==='erase'?'#ffffff88':'#ffd54a',drawingTool==='erase'?16/boardZoom:2);
 if(preview)$('links').append(preview);
 canvas.setPointerCapture(event.pointerId);canvas.style.cursor=pan?'grabbing':drawingTool==='erase'?'cell':'crosshair';
 const move=e=>{if(pan){canvas.scrollLeft=start.left+start.x-e.clientX;canvas.scrollTop=start.top+start.y-e.clientY;}else{points.push(boardPoint(e));preview.setAttribute('d',points.map((p,i)=>`${i?'L':'M'}${p.x},${p.y}`).join(' '));}};
 const cleanup=()=>{canvas.removeEventListener('pointermove',move);canvas.removeEventListener('pointerup',finish);canvas.removeEventListener('pointercancel',cancel);preview?.remove();canvas.style.cursor='';};
 const finish=e=>{move(e);cleanup();if(pan)return;const tool=drawingTool;edit(()=>{if(tool==='erase')eraseBoardDrawing(board(),points,8/boardZoom);else if(points.length>1)(board().strokes||=[]).push({id:uuid(),points,color:'#ffd54a',width:2});});};
 const cancel=()=>cleanup();canvas.addEventListener('pointermove',move);canvas.addEventListener('pointerup',finish);canvas.addEventListener('pointercancel',cancel);
},true);
$('canvas').addEventListener('dblclick',event=>{
  if(event.target.closest('[data-beat-id],.block-title,button,input'))return;
  const frame=$('canvas').getBoundingClientRect(),g=geometry(),x=boardPoint(event).x,y=boardPoint(event).y;
  const layer=board().layers.find(l=>{const r=g.layers.get(l.id);return y>=r.y&&y<r.y+r.height;});if(!layer)return;
  const parent=board().blocks.find(b=>b.id===event.target.closest('[data-block-id]')?.dataset.blockId&&!b.standalone);
  beginInlineBeat(layer.id,{x:Math.max(0,x-110),y:Math.max(32,y-g.layers.get(layer.id).y)},parent?.id);
});
$('canvas').addEventListener('pointerdown',e=>{
 const cause=e.target.closest('[data-beat-id]')?.dataset.beatId;if(!e.altKey||!cause||current.access==='reader')return;
 e.preventDefault();e.stopImmediatePropagation();const canvas=$('canvas');canvas.setPointerCapture(e.pointerId);
 canvas.addEventListener('pointerup',event=>{const frame=canvas.getBoundingClientRect(),x=boardPoint(event).x,y=boardPoint(event).y;const hit=[...geometry().beats].find(([,r])=>x>=r.x&&x<=r.x+r.width&&y>=r.y&&y<=r.y+r.height);if(hit&&hit[0]!==cause)edit(()=>{board().dependencies.push({id:uuid(),cause,effect:hit[0],reason:'',reference:false});});},{once:true});
},true);
document.addEventListener('keydown',e=>{if(e.target!==$('canvas')||!(e.ctrlKey||e.metaKey)||!selected)return;if(e.key.toLowerCase()==='i'){e.preventDefault();source=selected;status('Select the effect, then press Command/Ctrl+O');}if(e.key.toLowerCase()==='o'&&source){e.preventDefault();const cause=source;edit(()=>{board().dependencies.push({id:uuid(),cause,effect:selected,reason:'',reference:false});});source=null;}});
let pushEnabled=false;
const pushButton=element('button','Push');pushButton.setAttribute('aria-pressed','false');pushButton.onclick=()=>{pushEnabled=!pushEnabled;pushButton.setAttribute('aria-pressed',String(pushEnabled));};$('fit').after(pushButton);
$('canvas').addEventListener('pointerdown',e=>{
 if(!(pushEnabled||e.ctrlKey||e.metaKey)||e.button!==0||current.access==='reader')return;e.preventDefault();e.stopImmediatePropagation();
 const canvas=$('canvas'),frame=canvas.getBoundingClientRect(),start=e.clientX,pivot=boardPoint(e).x-110;canvas.setPointerCapture(e.pointerId);canvas.style.cursor='ew-resize';
 const finish=event=>{canvas.removeEventListener('pointerup',finish);canvas.removeEventListener('pointercancel',cancel);canvas.style.cursor='';const distance=(event.clientX-start)/boardZoom;if(Math.abs(distance)>3)edit(()=>{doc.project.frontstageWhiteboard=spatialOrder(pushBoard(board(),pivot,distance));});};
 const cancel=()=>{canvas.removeEventListener('pointerup',finish);canvas.style.cursor='';};canvas.addEventListener('pointerup',finish,{once:true});canvas.addEventListener('pointercancel',cancel,{once:true});
},true);
let boardMenu=null;
function closeBoardMenu(){boardMenu?.remove();boardMenu=null;}
$('canvas').addEventListener('contextmenu',event=>{
  event.preventDefault();closeBoardMenu();const frame=$('canvas').getBoundingClientRect(),g=geometry(),x=boardPoint(event).x,y=boardPoint(event).y;
  const beat=board().beats.find(b=>b.id===event.target.closest('[data-beat-id]')?.dataset.beatId),block=board().blocks.find(b=>b.id===event.target.closest('[data-block-id]')?.dataset.blockId),layer=board().layers.find(l=>{const r=g.layers.get(l.id);return y>=r.y&&y<r.y+r.height;});if(!layer)return;
  const menu=element('div',undefined,'board-context-menu');boardMenu=menu;menu.setAttribute('role','menu');menu.setAttribute('aria-label','Whiteboard actions');
  const item=(label,run,disabled=false)=>{const button=element('button',label);button.setAttribute('role','menuitem');button.disabled=disabled;button.onclick=()=>{closeBoardMenu();run();};menu.append(button);};
  const readOnly=current.access==='reader',uneditable=readOnly||layer.locked||(block&&locked({blockID:block.id}));
  if(beat){
    if(!selectedBeats.has(beat.id)){selectedBeats=new Set([beat.id]);selected=beat.id;}
    item('Edit Beat',()=>openEditor(beat.id));item('Jump to Script',()=>{$('script').hidden=false;const text=document.querySelector(`[data-script-beat="${beat.id}"]`);if(text){text.closest('.script-beat-body').hidden=false;text.scrollIntoView({block:'start'});}});
    item('Duplicate Beat',()=>{let id;edit(()=>{id=duplicateBeat(doc,beat.id);});if(id)choose(id);},uneditable||beat.locked);
    if(block?.containerKind==='beatGroup')item('Split Group Here',()=>edit(()=>{doc.project.frontstageWhiteboard=splitGroupAt(board(),beat.id);}),uneditable||beat.locked);
    item('Group Selected Beats',()=>edit(()=>{doc.project.frontstageWhiteboard=groupBeats(board(),selectedBeats,uuid());}),uneditable||beat.locked);
    item('Create Dependency From',()=>{source=beat.id;status('Select the effect beat');},uneditable||beat.locked);
    item(selectedBeats.size>1?'Pull Out Selected Beats':'Pull Out Beat',()=>edit(()=>{doc=pullOutBeats(doc,selectedBeats);}),uneditable||[...selectedBeats].some(id=>locked(board().beats.find(b=>b.id===id))));
    item(beat.omitted?'Include Beat':'Omit Beat',()=>edit(()=>{beat.omitted=!beat.omitted;}),uneditable||beat.locked);
  }
  if(block&&!block.standalone){
    item('Rename '+(block.containerKind==='beatGroup'?'Group':'Block'),()=>{const name=prompt('Container name',block.name);if(name?.trim())edit(()=>{block.name=name.trim();});},uneditable);
    item(block.collapsed?'Expand Container':'Collapse Container',()=>edit(()=>{block.collapsed=!block.collapsed;}),readOnly);
    item('Container Synopsis…',()=>{const value=prompt('Synopsis',block.synopsis??'');if(value!==null)edit(()=>{block.synopsis=value;});},uneditable);
    if(block.containerKind!=='beatGroup')item('Split Block Here',()=>edit(()=>{doc.project.frontstageWhiteboard=splitBlockAt(board(),block.id,x-110);}),uneditable);
    if(selectedBlocks.size>1)item('Merge Groups / Blocks',()=>edit(()=>{doc.project.frontstageWhiteboard=mergeContainers(board(),selectedBlocks);}),uneditable);
    item('Ungroup Container',()=>edit(()=>{doc.project.frontstageWhiteboard=ungroupBlocks(board(),new Set([block.id]));}),uneditable);
    item('Pull Out Container Contents',()=>edit(()=>{const containers=descendantBlocks(board(),new Set([block.id]));doc=pullOutBeats(doc,new Set(board().beats.filter(b=>containers.has(b.blockID)).map(b=>b.id)));}),uneditable);
  }
  const position={x:Math.max(0,x-110),y:Math.max(32,y-g.layers.get(layer.id).y)},parent=block&&!block.standalone?block.id:null;
  for(const kind of ['beat','group','block','lane'])item('Add '+kind[0].toUpperCase()+kind.slice(1)+' Here',()=>createPalette(kind,layer.id,position,['beat','group'].includes(kind)?parent:null),uneditable||(kind==='block'&&!usesBlocks(board(),layer.id))||(['beat','group'].includes(kind)&&usesBlocks(board(),layer.id)&&!parent));
  item(usesBlocks(board(),layer.id)?'Disable Use Blocks':'Enable Use Blocks',()=>edit(()=>{layer.useBlocks=!usesBlocks(board(),layer.id);}),readOnly||layer.locked);
  item('Undo',()=>restoreHistory(history,future),readOnly||!history.length);
  menu.style.left=Math.max(4,Math.min(event.clientX,window.innerWidth-260))+'px';menu.style.top=Math.max(4,Math.min(event.clientY,window.innerHeight-440))+'px';document.body.append(menu);menu.querySelector('button:not(:disabled)')?.focus();
  menu.onkeydown=e=>{const buttons=[...menu.querySelectorAll('button:not(:disabled)')],index=buttons.indexOf(document.activeElement);if(e.key==='Escape'){closeBoardMenu();$('canvas').focus();}if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();buttons[(index+(e.key==='ArrowDown'?1:buttons.length-1))%buttons.length]?.focus();}};
});
document.addEventListener('pointerdown',event=>{if(boardMenu&&!boardMenu.contains(event.target))closeBoardMenu();});window.addEventListener('resize',closeBoardMenu);
function download() { if (!doc) return; const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' }); const link = element('a'); link.href = URL.createObjectURL(blob); link.download = projectFilename(doc.name); link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 1000); }
async function authenticate(signup = false) {
  const form = new FormData($('login')); $('auth-error').textContent = '';
  try { setServer(); const { data } = await api(`/api/${signup ? 'signup' : 'login'}`, 'POST', Object.fromEntries(form)); token = data.token; $('login').reset(); $('server-address').value = apiOrigin; await loadProjects(); status(`Signed in as ${data.username}`); }
  catch (error) { $('auth-error').textContent = error.message; }
}
$('login').onsubmit = e => { e.preventDefault(); authenticate(); }; $('signup').onclick = () => authenticate(true);
$('local-mode').onclick = () => loadLocalProjects().catch(e => status(e.message));
$('new-project').onclick = async () => { const name = prompt('Project name', 'Untitled Story'); if (!name) return; try { const document = emptyDocument(name); if (localMode) { await createLocalProject(name, document); return; } const { data } = await api('/api/projects', 'POST', { document }); await openProject(data.id); } catch (error) { status(error.message); } };
$('import-project').onchange = async e => { try { const file = e.target.files[0]; if (!file) return; const document = initializeBoard(parseProjectFile(await file.text(),file.name)); if (localMode) { await createLocalProject(document.name, document); return; } const { data } = await api('/api/projects', 'POST', { document }); await openProject(data.id); } catch (error) { status(error.message); } };
$('logout').onclick = async () => { await saveLocal(); ++documentEpoch; clearTimeout(timer); if (token) { try { await api('/api/logout', 'POST'); } catch {} } token = ''; current = null; doc = null; dirty = false; localMode = false; pendingConflict = null; $('conflict').hidden = true; $('workspace').hidden = true; $('project-toolbar').hidden = true; $('projects').hidden = true; $('account').hidden = false; closeEditors(); status('Local projects and drafts remain in this browser'); };
$('back').onclick = async () => { await saveLocal(); closeEditors(); editorID = null; (localMode ? loadLocalProjects() : loadProjects()).catch(e => status(e.message)); };
$('save').onclick = sync; $('download').onclick = download; $('export-conflict').onclick = download;
$('undo').onclick = () => restoreHistory(history, future); $('redo').onclick = () => restoreHistory(future, history);
for(const id of ['undo','redo'])$(id).addEventListener('pointerdown',event=>event.preventDefault());
$('board-actions').onchange = () => {
  const action = $('board-actions').value; $('board-actions').value = '';
  if (action === 'marker') { editMarker(); return; }
  if (action === 'group') {
    const name = prompt('Block name', 'New Block'); if (name === null) return;
    const id = uuid(); edit(() => { doc.project.frontstageWhiteboard = groupBlocks(board(), selectedBlocks.size?selectedBlocks:new Set(board().beats.filter(b=>selectedBeats.has(b.id)).map(b=>b.blockID)), name, id); });
    if (board().blocks.some(b => b.id === id)) { selectedBlocks = new Set([id]); render(); } return;
  }
  if (action === 'ungroup') edit(() => { doc.project.frontstageWhiteboard = ungroupBlocks(board(), selectedBlocks); });
  if (action === 'compact') edit(() => { doc.project.frontstageWhiteboard = compactCausalTime(board()); });
  if (action === 'delete') edit(() => { const ids=descendantBlocks(board(),selectedBlocks);doc=pullOutBeats(doc,new Set(board().beats.filter(b=>ids.has(b.blockID)).map(b=>b.id))); });
};
$('timeline-toggle').onclick = () => { $('timeline').hidden = !$('timeline').hidden; };
$('properties-toggle').onclick = () => { $('properties').hidden = !$('properties').hidden; };
$('script-toggle').onclick = () => { $('script').hidden = !$('script').hidden; highlightScript(true); };
$('add-group').onclick=()=>{const ids=selectedBeats.size?selectedBeats:new Set(selected?[selected]:[]);if(!ids.size){selected=null;addBeat(false,null,true);}else edit(()=>{doc.project.frontstageWhiteboard=groupBeats(board(),ids,uuid());});};
$('add-beat').onclick = () => addBeat(true); $('add-to-block').onclick = () => addBeat(); $('add-block').onclick = () => {const owner=board().blocks.find(b=>b.id===board().beats.find(b=>b.id===selected)?.blockID);createPalette('block',owner?.layerID??board().layers[0].id,{x:Math.max(60,...board().blocks.map(b=>b.position.x+b.width+40)),y:70});};
$('add-layer').onclick = () => { const name = prompt('Layer name', 'New Layer'); if (name) edit(() => board().layers.push({ id: uuid(), name, height: 300, collapsed: false, locked: false, unused: false, useBlocks:false })); };
$('cause').onclick = () => { if (selected) { source = selected; status('Select the effect beat'); } };
$('resolve').onclick = () => edit(resolve);
$('fit').onclick = () => {
  if(!doc)return;const g=geometry(),chosen=[...selectedBeats].map(id=>g.beats.get(id)).filter(Boolean),rects=chosen.length?chosen:[...g.blocks.values()];if(!rects.length){zoomBoard(1);return;}
  const left=Math.min(...rects.map(r=>r.x))-30,top=Math.min(...rects.map(r=>r.y))-30,right=Math.max(...rects.map(r=>r.x+r.width))+30,bottom=Math.max(...rects.map(r=>r.y+r.height))+30,canvas=$('canvas');
  zoomBoard(Math.min(canvas.clientWidth/(right-left),canvas.clientHeight/(bottom-top)));canvas.scrollLeft=Math.max(0,left*boardZoom);canvas.scrollTop=Math.max(0,top*boardZoom);
};
$('keep-local').onclick = () => { if (!pendingConflict) return; base = clone(pendingConflict.document); current.revision = pendingConflict.revision; pendingConflict = null; $('conflict').hidden = true; dirty = true; sync(); };
$('take-server').onclick = async () => { if (!pendingConflict) return; download(); doc = initializeBoard(clone(pendingConflict.document)); base = clone(pendingConflict.document); current.revision = pendingConflict.revision; dirty = false; pendingConflict = null; $('conflict').hidden = true; closeEditors(); editorID = null; await saveLocal(); render(); status('Server copy loaded; previous local copy downloaded'); };
$('share').onclick = async () => { if (current?.local) { status('Download your local project, sign in, then import it to create a shared copy.'); return; } if (!current || current.access !== 'owner') { status('Only the project owner can change access'); return; } const username = prompt('Existing account username'); if (!username) return; const access = prompt('Access: reader or editor', 'editor'); if (!['reader', 'editor'].includes(access)) return; try { await api(`/api/projects/${current.id}/members`, 'POST', { username, access }); status(`Shared with ${username} (${access})`); } catch (error) { status(error.message); } };
document.addEventListener('keydown', e => { if (e.key === 'Escape') { if (editorID) closeEditor(editorID); source = null; } if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); sync(); } if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName) && !e.target.isContentEditable) { e.preventDefault(); if (e.shiftKey) restoreHistory(future, history); else restoreHistory(history, future); } if (e.key === 'Enter' && !e.isComposing && e.target === $('canvas')) {e.preventDefault();const owner=board().blocks.find(b=>b.id===board().beats.find(b=>b.id===selected)?.blockID);addBeat(!owner||!!owner.standalone,selected);} });
window.addEventListener('online', () => { if (dirty) sync(); });
window.addEventListener('beforeunload', e => { if (dirty) { e.preventDefault(); e.returnValue = ''; } });
setInterval(async () => {
  if (!current || current.local || !token || dirty || syncing || editorID || document.activeElement?.isContentEditable || pendingConflict) return;
  const epoch = documentEpoch, projectID = current.id;
  try {
    const { data } = await api(`/api/projects/${projectID}`);
    if (epoch !== documentEpoch || current?.id !== projectID || dirty || syncing || editorID || document.activeElement?.isContentEditable || pendingConflict) return;
    if (data.revision !== current.revision) { const nextDocument = initializeBoard(clone(data.document)); current = data; base = clone(data.document); doc = nextDocument; render(); await saveLocal(); status(`Updated · revision ${current.revision}`); }
  } catch {}
}, 5000);

const workspaces = mountWorkspaces({
  undo:()=>restoreHistory(history,future),redo:()=>restoreHistory(future,history),
  createConvertedCopy: document=>createLocalProject(document.name,document),
  document: () => doc, current: () => current, edit, status, cleanHTML, plain,
  selectedBeat: () => selected,
  selectedScene: () => board().beats.find(b => b.id === selected)?.sceneID,
  selectScene: (id, beatID) => { const beat = board().beats.find(b => b.id === beatID) || board().beats.find(b => b.sceneID === id); if (beat) { selected = beat.id; selectedBeats = new Set([selected]); } },
  selectBeat: id => choose(id), openBeat: openEditor,
  addScene: () => { selected = null; addBeat(true); if (selected) closeEditor(selected); },
  projects: () => $('back').click(), sync, download,
  refresh: async () => {
    await sync();
    if (!current || current.local || dirty || syncing || pendingConflict) return;
    const epoch=documentEpoch,id=current.id;
    const {data}=await api(`/api/projects/${id}`);
    if(epoch!==documentEpoch||dirty||syncing||pendingConflict)return;
    const next=initializeBoard(clone(data.document));
    current=data;base=clone(data.document);doc=next;render();await saveLocal();status(`Synced · revision ${current.revision}`);
  },
  duplicate: async () => { const document=clone(doc);document.name+=' copy';const {data}=await api('/api/projects','POST',{document});await openProject(data.id); },
  connect: () => { download(); $('logout').click(); },
  share: async (username, access) => { if (!username.trim()) throw Error('Enter a registered username.'); await api(`/api/projects/${current.id}/members`, 'POST', {username, access: access === 'remove' ? null : access}); status(`Access updated for ${username}`); }
});

// Re-measure cards if a fallback/web font finishes loading after the first render.
document.fonts?.addEventListener('loadingdone', () => { if (doc) render(); });

document.addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='l'&&selectedBeats.size&&(event.target===$('canvas')||$('script').contains(event.target))&&!event.target.isContentEditable&&!['INPUT','TEXTAREA'].includes(event.target.tagName)){event.preventDefault();scriptFilter.set({...scriptFilter.state,facets:{...scriptFilter.state.facets,Beats:{values:[...selectedBeats],hide:false,all:false}}});render();}});

$('canvas').addEventListener('keydown',event=>{if(event.target===$('canvas')&&['Delete','Backspace'].includes(event.key)&&!event.isComposing){event.preventDefault();if(selectedBlocks.size)edit(()=>{const ids=descendantBlocks(board(),selectedBlocks);doc=pullOutBeats(doc,new Set(board().beats.filter(b=>ids.has(b.blockID)).map(b=>b.id)));});else if(selectedBeats.size)edit(()=>{doc=pullOutBeats(doc,selectedBeats);});}});
