import { mountWorkspaces } from './workspaces.js';
import { splitAtCaret, screenplayToolbar } from './screenplay-editor.js';
import { splitBeat, scriptSegments, heading } from './workspace-model.js';
import { mergeDocuments } from './merge.js';
import { apiOrigin as configuredOrigin } from './config.js';
import { causalOrder as orderCauses, compactCausalTime, groupBlocks, ungroupBlocks, moveBlocks, moveStandaloneBeats, descendantBlocks, deleteBlocks, validateBoard, groupBeats, beatSize } from './board-operations.js';

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
    if (target instanceof HTMLElement) target.className = [...node.classList].filter(c => /^sc-(line|action|character|dialogue|parenthetical|transition|shot|lyrics|slugline)$/.test(c)).join(' ');
    for (const child of node.childNodes) target.append(clean(child));
    return target;
  }
  const result = document.createElement('div');
  for (const child of parsed.body.childNodes) result.append(clean(child));
  return result.innerHTML;
}
function plain(html) { const node = document.createElement('div'); node.innerHTML = cleanHTML(html); return node.textContent; }
async function api(path, method = 'GET', body) {
  const response = await fetch(apiOrigin + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!(response.headers.get('Content-Type') || '').includes('application/json') && response.status !== 204) throw Error('Shared service unavailable. Enter your Frontstage server address to sign in.');
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
  const snapshot = { id: current.id, doc: clone(doc), base: clone(base), revision: current.revision, dirty, local: !!current.local, name: doc.name };
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
function emptyDocument(name) { return initializeBoard({ format: 'frontstage', version: 1, name, project: { beats: [], nextId: 1 } }); }
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
      version: 1, layers: [{ id: 'main', name: 'Main Layer', height: 360, collapsed: false, locked: false, unused: false }, { id: 'unused', name: 'Unused', height: 300, collapsed: false, locked: false, unused: true }],
      blocks: beats.map((b, i) => ({ id: `block-${b.id}`, name: b.title, layerID: 'main', position: { x: b.x || i * 260, y: 60 }, width: 224, collapsed: false, locked: false })),
      beats: beats.map((b, i) => ({ id: `scene-${b.id}`, sceneID: b.id, blockID: `block-${b.id}`, title: b.title, synopsis: b.summary || '', html: b.content || '', kind: 'story', color: '#a34eae', characters: b.characters || [], tags: [], mustBeCaused: false, omitted: !!b.isDisabled, locked: false, order: i, start: i * 1.5, duration: 1.5 })),
      dependencies: (document.project.connections || []).filter(l => beats.some(b => b.id === l.from) && beats.some(b => b.id === l.to)).map(l => ({ id: uuid(), cause: `scene-${l.from}`, effect: `scene-${l.to}`, reason: l.label || '', reference: l.frontstageKind === 'reference' })),
      strokes: [], viewport: { origin: { x: 0, y: 0 }, zoom: 1 }
    };
  }
  if (document.project.frontstageWhiteboard.version !== 1) throw Error('Unsupported whiteboard version');
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
function edit(action) {
  if (!doc || current.access === 'reader') return;
  const previous = clone(doc);
  try { action(); validateBoard(board(), new Set(doc.project.beats.map(s => s.id))); compileSnippets(); if (equal(previous, doc)) return; history.push(previous); future.length = 0; if (history.length > 40) history.shift(); dirty = true; saveLocal().catch(e => status(`Local save failed: ${e.message}`)); render(); clearTimeout(timer); timer = setTimeout(sync, 800); }
  catch (error) { doc = previous; render(); status(error.message); }
}
function restoreHistory(from, to) {
  if (!doc || current.access === 'reader' || !from.length) return;
  to.push(clone(doc)); doc = from.pop(); dirty = true;
  refreshEditors(true);
  saveLocal().catch(e => status(`Local save failed: ${e.message}`)); render(); clearTimeout(timer); timer = setTimeout(sync, 800);
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
    const { data, status: code } = await api(`/api/projects/${projectID}`, 'PUT', { expectedRevision: revision, changeID: uuid(), document: sent });
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
  selected = id; render(); $('canvas').focus({preventScroll:true});
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
      const rect = { x: block.position.x + 110, y: block.position.y + y, width: block.width, height: block.collapsed ? 28 : Math.max(60, children.reduce((h,b)=>h+beatSize(b.title,block.width-12).height+4,32)) };
      blocks.set(block.id, rect); maxX = Math.max(maxX, rect.x + rect.width + 120);
      if (!block.collapsed) { let top=rect.y+24;for(const beat of children){const size=beatSize(beat.title,block.width-12);beats.set(beat.id,{x:rect.x+6,y:top,...size});top+=size.height+4;} }
    }
    y += height;
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
  maxX = Math.max(maxX, ...storyMarkers().map(m => 110 + m.unit * 120 + 200));
  return { blocks, beats, layers, width: maxX, height: Math.max(800, y) };
}
function position(node, rect) { node.style.left = `${rect.x}px`; node.style.top = `${rect.y}px`; node.style.width = `${rect.width}px`; node.style.height = `${rect.height}px`; }
function render() {
  const editingSide=document.activeElement?.hasAttribute('data-script-beat');
  if (!doc) return;
  const beatIDs = new Set(board().beats.map(b => b.id)), blockIDs = new Set(board().blocks.map(b => b.id));
  selectedBeats = new Set([...selectedBeats].filter(id => beatIDs.has(id))); selectedBlocks = new Set([...selectedBlocks].filter(id => blockIDs.has(id)));
  if (!beatIDs.has(selected)) selected = null;
  const g = geometry(), issues = storyIssues(), warning = new Set(issues.map(i => i.id));
  $('layers').replaceChildren(); $('blocks').replaceChildren(); $('links').replaceChildren(); if(!editingSide)$('snippet-list').replaceChildren(); $('issues').replaceChildren();
  for (const layer of board().layers) {
    const rect = g.layers.get(layer.id), node = element('div', undefined, 'layer'); position(node, { x: 0, y: rect.y, width: g.width, height: rect.height });
    const label = element('button', `${layer.collapsed ? '▸' : '▾'} ${layer.name}`, 'layer-label'); label.onclick = () => edit(() => { layer.collapsed = !layer.collapsed; }); node.append(label); $('layers').append(node);
  }
  const blockOrder = [...board().blocks].sort((a, b) => { const x = g.blocks.get(a.id), y = g.blocks.get(b.id); return (y ? y.width * y.height : 0) - (x ? x.width * x.height : 0); });
  for (const block of blockOrder) {
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
      title.onpointermove = event => { for (const item of nodes) { const r = g.blocks.get(item.dataset.blockId); item.style.left = `${r.x + event.clientX - start.x}px`; item.style.top = `${r.y + event.clientY - start.y}px`; } };
      title.onpointerup = event => { title.onpointermove = null; title.onpointerup = null; if (selectedBlocks.size) edit(() => { doc.project.frontstageWhiteboard = moveBlocks(board(), selectedBlocks, event.clientX - start.x, event.clientY - start.y); }); render(); };
      title.onpointercancel = () => { title.onpointermove = null; title.onpointerup = null; render(); };
    };
    node.ondragover = e => e.preventDefault(); node.ondrop = e => {
      e.preventDefault(); e.stopPropagation(); const id = e.dataTransfer.getData('text/frontstage-beat'), moving = board().beats.find(b => b.id === id); if (!moving || locked(moving) || locked({ blockID: block.id })) return;
      if (moving.blockID === block.id && block.standalone) { dropStandaloneBeats(e); return; }
      edit(() => { moving.blockID = block.id; moving.order = Math.max(-1, ...board().beats.filter(b => b.blockID === block.id && b.id !== id).map(b => b.order)) + 1; });
    };
    if (!block.collapsed) for (const beat of board().beats.filter(b => b.blockID === block.id).sort((a, b) => a.order - b.order)) {
      const tile = element('div', undefined, `beat${selectedBeats.has(beat.id) ? ' selected' : ''}`); tile.style.backgroundColor = /^#[a-f0-9]{6}$/i.test(beat.color) ? beat.color : '#a34eae';
      tile.dataset.beatId = beat.id;
      const card=g.beats.get(beat.id);if(card){tile.style.position='absolute';position(tile,{...card,x:card.x-rect.x,y:card.y-rect.y});}
      tile.append(element('span', beat.title, 'beat-text')); tile.draggable = current.access !== 'reader' && !locked(beat);
      if (warning.has(beat.id)) tile.append(element('span', '!', 'badge'));
      tile.onclick = e => { e.stopPropagation(); choose(beat.id, e.shiftKey); }; tile.ondblclick = () => openEditor(beat.id);
      tile.ondragstart = e => {
        e.dataTransfer.setData('text/frontstage-beat', beat.id);
        const frame = node.getBoundingClientRect();
        e.dataTransfer.setData('text/frontstage-grab-offset', `${e.clientX - frame.left},${e.clientY - frame.top}`);
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
  for (const marker of storyMarkers()) {
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'path'), x = 110 + marker.unit * 120;
    line.setAttribute('d', `M${x},0 V${g.height}`); line.setAttribute('stroke', '#4d8ed6'); line.setAttribute('stroke-dasharray', '3 5'); $('links').append(line);
  }
  if(!editingSide) for (const segment of scriptSegments(doc)) {
    $('snippet-list').append(element('h3',`${segment.number}  ${heading(segment.scene)}${segment.continuation?' (CONTINUED)':''}`,'script-heading'));
    for(const id of segment.beatIDs){const beat=board().beats.find(b=>b.id===id),text=element('div',undefined,'side-script-text script-text');text.innerHTML=cleanHTML(beat.html);text.dataset.scriptBeat=id;text.tabIndex=0;text.setAttribute('aria-label',`Edit script: ${beat.title}`);text.contentEditable=current.access!=='reader'&&!segment.scene.frontstageTextLocked;text.setAttribute('role','textbox');text.onfocus=()=>{selected=id;selectedBeats=new Set([id]);};text.oninput=()=>edit(()=>{board().beats.find(b=>b.id===id).html=cleanHTML(text.innerHTML);});text.ondblclick=()=>openEditor(id);$('snippet-list').append(text);}
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
  refreshEditors();
  workspaces.render();
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
function renderTimeline() {
  const markers = storyMarkers(), end = Math.max(20, ...board().beats.map(b => b.start + b.duration), ...markers.map(m => m.unit + 3)), scale = 22;
  const ruler = element('div', undefined, 'ruler'); ruler.style.width = `${end * scale + 90}px`;
  for (let i = 0; i <= end; i += Math.max(5, Math.ceil(end / 100))) { const mark = element('span', String(i)); mark.style.left = `${90 + i * scale}px`; ruler.append(mark); }
  const track = element('div', undefined, 'track'), snippets = element('div', undefined, 'track'); track.style.width = ruler.style.width; snippets.style.width = ruler.style.width;
  for (const beat of board().beats) {
    for (const [row, isSnippet] of [[track, false], [snippets, true]]) {
      const tile = element('div', isSnippet ? '' : doc.project.beats.find(s => s.id === beat.sceneID)?.title || beat.title, 'time-beat'); tile.style.left = `${90 + beat.start * scale}px`; tile.style.width = `${Math.max(8, beat.duration * scale - 1)}px`; tile.style.backgroundColor = isSnippet ? beat.color : '#3c65a8'; tile.onclick = () => choose(beat.id); row.append(tile);
    }
  }
  const acts = element('div', undefined, 'track'); acts.style.width = ruler.style.width;
  for (const marker of markers) {
    const tag = element('button', marker.title || 'Marker', 'act-marker'); tag.style.left = `${90 + marker.unit * scale}px`;
    tag.onclick = () => editMarker(marker); tag.oncontextmenu = event => { event.preventDefault(); if (current.access !== 'reader' && confirm(`Remove “${marker.title}”?`)) edit(() => { doc.project.sectionBreaks = doc.project.sectionBreaks.filter(m => m.id !== marker.id); }); };
    acts.append(tag);
  }
  $('timeline').style.height = markers.length ? '105px' : '85px';
  $('timeline').replaceChildren(...(markers.length ? [ruler, acts, track, snippets] : [ruler, track, snippets]));
}
function storyMarkers() {
  const seen = new Set();
  return (Array.isArray(doc.project.sectionBreaks) ? doc.project.sectionBreaks : []).filter(m => m && typeof m.id === 'string' && Number.isFinite(m.unit) && m.unit >= 0 && m.unit <= 1000000 / 120 && !seen.has(m.id) && seen.add(m.id)).sort((a, b) => a.unit - b.unit || a.id.localeCompare(b.id));
}
function editMarker(marker = null) {
  if (current.access === 'reader') return;
  const title = prompt('Act / marker name', marker?.title || `Act ${storyMarkers().length + 1}`); if (!title?.trim()) return;
  const raw = prompt('Estimated story time', String(marker?.unit ?? board().beats.find(b => b.id === selected)?.start ?? 0)); if (raw === null) return;
  const unit = Number(raw);
  edit(() => {
    if (!Number.isFinite(unit) || unit < 0 || unit > 1000000 / 120) throw Error('Choose a valid estimated story time.');
    if (doc.project.sectionBreaks !== undefined && !Array.isArray(doc.project.sectionBreaks)) throw Error('Existing marker data has an unsupported format.');
    doc.project.sectionBreaks ||= [];
    if (marker) { const stored = doc.project.sectionBreaks.find(m => m.id === marker.id); if (stored) { stored.title = title; stored.unit = unit; } }
    else doc.project.sectionBreaks.push({ id: uuid(), title, unit, type: 'custom' });
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
    const text = panel.querySelector('[data-field="snippet-editor"]'), html = cleanHTML(beat.html);
    if (cleanHTML(text.innerHTML) !== html) text.innerHTML = html;
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
  if (editors.has(id)) { activateEditor(id); editors.get(id).querySelector('[data-field="snippet-editor"]').focus(); return; }
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
  field('editor-label').style.backgroundColor = /^#[a-f0-9]{6}$/i.test(beat.color) ? beat.color : '#a34eae';
  const text = field('snippet-editor'); text.innerHTML = cleanHTML(beat.html);
  text.contentEditable = current.access === 'reader' || doc.project.beats.find(s => s.id === beat.sceneID)?.frontstageTextLocked ? 'false' : 'true';
  text.oninput = () => { const html = cleanHTML(text.innerHTML); edit(() => { const target = board().beats.find(b => b.id === id); if (target) target.html = html; }); };
  field('element').parentElement.replaceWith(screenplayToolbar(text, () => text.dispatchEvent(new Event('input')), text.contentEditable === 'true'));
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
  field('beat-title').focus();
}
function addBeat(standalone = false, afterID = null, asGroup = false) {
  edit(() => {
    const previous=board().beats.find(b=>b.id===afterID),previousBlock=board().blocks.find(b=>b.id===previous?.blockID);const owner = standalone ? null : board().beats.find(b => b.id === selected); let blockID = owner?.blockID, sceneID = previous?.sceneID??owner?.sceneID;
    if((owner&&locked(owner))||(previous&&locked(previous)))throw Error('Unlock the destination before adding a beat.');
    if (!blockID) {
      blockID = uuid(); if(sceneID==null){ sceneID = Math.max(0, ...doc.project.beats.map(b => Number(b.id))) + 1;
      doc.project.beats.push({ id: sceneID, title: 'Untitled Scene', content: '', slug: { prefix: 'INT.', location: '', time: 'DAY' }, boardId: 0 }); doc.project.nextId = sceneID + 1; }
      const right = Math.max(-244, ...board().blocks.map(b => b.position.x + b.width));
      board().blocks.push({ standalone, id: blockID, name: asGroup?'Beat Group':'Untitled Block', ...(asGroup?{containerKind:'beatGroup'}:{}), layerID: previousBlock?.layerID??board().layers[0].id, position: previousBlock ? {x:previousBlock.position.x,y:previousBlock.position.y+beatSize(previous.title,previousBlock.width-12).height+12} : { x: Math.max(40, right + 60), y: 70 }, width: 224, collapsed: false, locked: false });
    }
    const beat = { id: uuid(), sceneID, blockID, title: 'Untitled Beat', synopsis: '', html: '', kind: 'story', color: '#a34eae', characters: [], tags: [], mustBeCaused: false, omitted: false, locked: false, order: Math.max(-1, ...board().beats.map(b => b.order)) + 1, start: Math.max(0, ...board().beats.map(b => b.start + b.duration)), duration: 1.5 };
    if(previous){const ordered=[...board().beats].sort((a,b)=>a.order-b.order),index=ordered.findIndex(b=>b.id===previous.id);beat.order=(previous.order+(ordered[index+1]?.order??previous.order+2))/2;}
    board().beats.push(beat); selected = beat.id; selectedBeats=new Set([beat.id]);
  }); openEditor(selected);
}
$('canvas').ondragover = e => e.preventDefault();
$('canvas').ondrop = dropStandaloneBeats;
function dropStandaloneBeats(e) {
  e.preventDefault();
  const id = e.dataTransfer.getData('text/frontstage-beat'), beat = board().beats.find(b => b.id === id);
  const block = board().blocks.find(b => b.id === beat?.blockID);
  if (!beat || !block?.standalone || locked(beat)) return;
  const frame = $('canvas').getBoundingClientRect(), rect = geometry().blocks.get(block.id);
  if (!rect) return;
  const offset = e.dataTransfer.getData('text/frontstage-grab-offset').split(',').map(Number);
  const [ox, oy] = offset.length === 2 && offset.every(Number.isFinite) ? offset : [0, 0];
  const ids = selectedBeats.has(id) ? selectedBeats : new Set([id]);
  edit(() => { doc.project.frontstageWhiteboard = moveStandaloneBeats(board(), ids, e.clientX - frame.left + $('canvas').scrollLeft - rect.x - ox, e.clientY - frame.top + $('canvas').scrollTop - rect.y - oy); });
}
function download() { if (!doc) return; const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' }); const link = element('a'); link.href = URL.createObjectURL(blob); link.download = `${doc.name || 'Story'}.frontstage`; link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 1000); }
async function authenticate(signup = false) {
  const form = new FormData($('login')); $('auth-error').textContent = '';
  try { setServer(); const { data } = await api(`/api/${signup ? 'signup' : 'login'}`, 'POST', Object.fromEntries(form)); token = data.token; $('login').reset(); $('server-address').value = apiOrigin; await loadProjects(); status(`Signed in as ${data.username}`); }
  catch (error) { $('auth-error').textContent = error.message; }
}
$('login').onsubmit = e => { e.preventDefault(); authenticate(); }; $('signup').onclick = () => authenticate(true);
$('local-mode').onclick = () => loadLocalProjects().catch(e => status(e.message));
$('new-project').onclick = async () => { const name = prompt('Project name', 'Untitled Story'); if (!name) return; try { const document = emptyDocument(name); if (localMode) { await createLocalProject(name, document); return; } const { data } = await api('/api/projects', 'POST', { document }); await openProject(data.id); } catch (error) { status(error.message); } };
$('import-project').onchange = async e => { try { const file = e.target.files[0]; if (!file) return; const document = initializeBoard(JSON.parse(await file.text())); if (localMode) { await createLocalProject(document.name, document); return; } const { data } = await api('/api/projects', 'POST', { document }); await openProject(data.id); } catch (error) { status(error.message); } };
$('logout').onclick = async () => { await saveLocal(); ++documentEpoch; clearTimeout(timer); if (token) { try { await api('/api/logout', 'POST'); } catch {} } token = ''; current = null; doc = null; dirty = false; localMode = false; pendingConflict = null; $('conflict').hidden = true; $('workspace').hidden = true; $('project-toolbar').hidden = true; $('projects').hidden = true; $('account').hidden = false; closeEditors(); status('Local projects and drafts remain in this browser'); };
$('back').onclick = async () => { await saveLocal(); closeEditors(); editorID = null; (localMode ? loadLocalProjects() : loadProjects()).catch(e => status(e.message)); };
$('save').onclick = sync; $('download').onclick = download; $('export-conflict').onclick = download;
$('undo').onclick = () => restoreHistory(history, future); $('redo').onclick = () => restoreHistory(future, history);
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
  if (action === 'delete') edit(() => { doc = deleteBlocks(doc, selectedBlocks); });
};
$('timeline-toggle').onclick = () => { $('timeline').hidden = !$('timeline').hidden; };
$('properties-toggle').onclick = () => { $('properties').hidden = !$('properties').hidden; };
$('script-toggle').onclick = () => { $('script').hidden = !$('script').hidden; };
$('add-group').onclick=()=>{const ids=selectedBeats.size?selectedBeats:new Set(selected?[selected]:[]);if(!ids.size){selected=null;addBeat(false,null,true);}else edit(()=>{doc.project.frontstageWhiteboard=groupBeats(board(),ids,uuid());});};
$('add-beat').onclick = () => addBeat(true); $('add-to-block').onclick = () => addBeat(); $('add-block').onclick = () => { selected = null; addBeat(); };
$('add-layer').onclick = () => { const name = prompt('Layer name', 'New Layer'); if (name) edit(() => board().layers.push({ id: uuid(), name, height: 300, collapsed: false, locked: false, unused: false })); };
$('cause').onclick = () => { if (selected) { source = selected; status('Select the effect beat'); } };
$('resolve').onclick = () => edit(resolve);
$('fit').onclick = () => { if (!doc) return; const rect = geometry().beats.get(selected); $('canvas').scrollTo({ left: Math.max(0, (rect?.x || 110) - 100), top: Math.max(0, (rect?.y || 60) - 80), behavior: 'smooth' }); };
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
  document: () => doc, current: () => current, edit, status, cleanHTML, plain,
  selectedBeat: () => selected,
  selectedScene: () => board().beats.find(b => b.id === selected)?.sceneID,
  selectScene: id => { const beat = board().beats.find(b => b.sceneID === id); if (beat) { selected = beat.id; selectedBeats = new Set([selected]); } },
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
