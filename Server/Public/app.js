import { mergeDocuments } from './merge.js';
import { apiOrigin as configuredOrigin } from './config.js';

const $ = id => document.getElementById(id);
const clone = value => structuredClone(value);
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const uuid = () => crypto.randomUUID();
let token = '', current = null, doc = null, base = null, selected = null, editorID = null, source = null;
let dirty = false, syncing = false, timer = null, pendingConflict = null;
let documentEpoch = 0;
let apiOrigin = '';
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
const status = text => { $('status').textContent = text; };
function element(tag, text, className) { const e = document.createElement(tag); if (text !== undefined) e.textContent = text; if (className) e.className = className; return e; }
function list(value) { return [...new Set(value.split(',').map(s => s.trim()).filter(Boolean))]; }
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
  const snapshot = { id: current.id, doc: clone(doc), base: clone(base), revision: current.revision, dirty };
  const db = await database;
  return new Promise((resolve, reject) => { const tx = db.transaction('projects', 'readwrite'); tx.objectStore('projects').put(snapshot); tx.oncomplete = resolve; tx.onerror = () => reject(tx.error); });
}
async function localCopy(id) {
  const db = await database;
  return new Promise((resolve, reject) => { const r = db.transaction('projects').objectStore('projects').get(id); r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error); });
}
function board() { return doc.project.frontstageWhiteboard; }
function initializeBoard(document) {
  if (document.format !== 'frontstage') document = { format: 'frontstage', version: 1, name: 'Imported Story', project: document };
  if (document.version !== 1 || !Array.isArray(document.project.beats)) throw Error('Unsupported project format');
  if (document.project.beats.some(beat => !Number.isSafeInteger(beat.id) || beat.id < 0)) throw Error('This project uses numeric identifiers outside browser precision. Open it with the native Swift client.');
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
  try { action(); compileSnippets(); history.push(previous); if (history.length > 40) history.shift(); dirty = true; saveLocal().catch(e => status(`Local save failed: ${e.message}`)); render(); clearTimeout(timer); timer = setTimeout(sync, 800); }
  catch (error) { doc = previous; status(error.message); }
}
async function sync() {
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
      else { doc = result.value; base = clone(data.snapshot.document); current.revision = data.snapshot.revision; dirty = true; render(); }
    } else {
      base = clone(data.snapshot.document); current.revision = data.snapshot.revision; current.access = data.snapshot.access;
      dirty = !equal(doc, sent); status(dirty ? 'More changes pending' : `Synced · revision ${current.revision}`);
    }
    await saveLocal();
  } catch (error) { if (epoch === documentEpoch) status(`Offline / sync failed · local copy retained: ${error.message}`); }
  finally { syncing = false; if (dirty && !pendingConflict && navigator.onLine) { clearTimeout(timer); timer = setTimeout(sync, 3000); } }
}
async function loadProjects() {
  const { data } = await api('/api/projects'); $('project-list').replaceChildren();
  for (const project of data) { const button = element('button', `${project.name} · ${project.access} · revision ${project.revision}`); button.onclick = () => openProject(project.id).catch(e => status(e.message)); $('project-list').append(button); }
  $('account').hidden = true; $('projects').hidden = false; $('workspace').hidden = true;
}
async function openProject(id) {
  const epoch = ++documentEpoch; clearTimeout(timer);
  const { data } = await api(`/api/projects/${id}`), offline = await localCopy(id);
  if (epoch !== documentEpoch) return;
  current = data; history.length = 0; selected = null; editorID = null; $('editor').hidden = true;
  pendingConflict = null; source = null; $('conflict').hidden = true;
  base = clone(data.document); doc = initializeBoard(clone(data.document)); dirty = !equal(doc, data.document);
  if (offline?.dirty) { base = offline.base; doc = initializeBoard(offline.doc); current.revision = offline.revision; dirty = true; }
  $('projects').hidden = true; $('workspace').hidden = false; render(); status(dirty ? 'Local changes ready to sync' : `Synced · revision ${current.revision}`);
  if (dirty) sync();
}
function choose(id) {
  if (source && source !== id) {
    const cause = source; source = null;
    edit(() => { if (board().dependencies.some(e => e.cause === cause && e.effect === id)) throw Error('Already connected'); board().dependencies.push({ id: uuid(), cause, effect: id, reason: '', reference: false }); causalOrder(); });
  }
  selected = id; render();
}
function causalOrder() {
  const incoming = new Map(board().beats.map(b => [b.id, 0])), outgoing = new Map();
  for (const edge of board().dependencies.filter(e => !e.reference)) { incoming.set(edge.effect, (incoming.get(edge.effect) || 0) + 1); if (!outgoing.has(edge.cause)) outgoing.set(edge.cause, []); outgoing.get(edge.cause).push(edge.effect); }
  const ready = board().beats.filter(b => !incoming.get(b.id)).sort((a, b) => a.order - b.order).map(b => b.id), result = [];
  while (ready.length) { const id = ready.shift(); result.push(id); for (const next of outgoing.get(id) || []) { incoming.set(next, incoming.get(next) - 1); if (!incoming.get(next)) ready.push(next); } }
  if (result.length !== board().beats.length) throw Error('A dependency would create a causal loop'); return result;
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
    const members = board().blocks.filter(b => b.layerID === layer.id), height = layer.collapsed ? 38 : Math.max(layer.height, ...members.map(b => b.position.y + board().beats.filter(t => t.blockID === b.id).length * 44 + 80));
    layers.set(layer.id, { y, height });
    if (!layer.collapsed) for (const block of members) {
      let parent = board().blocks.find(b => b.id === block.parentID), hidden = false; const seen = new Set();
      while (parent && !seen.has(parent.id)) { if (parent.collapsed) hidden = true; seen.add(parent.id); parent = board().blocks.find(b => b.id === parent.parentID); }
      if (hidden) continue;
      const children = board().beats.filter(b => b.blockID === block.id).sort((a, b) => a.order - b.order);
      const rect = { x: block.position.x + 110, y: block.position.y + y, width: block.width, height: block.collapsed ? 28 : Math.max(65, children.length * 44 + 32) };
      blocks.set(block.id, rect); maxX = Math.max(maxX, rect.x + rect.width + 120);
      if (!block.collapsed) children.forEach((beat, i) => beats.set(beat.id, { x: rect.x + 6, y: rect.y + 24 + i * 44, width: rect.width - 12, height: 40 }));
    }
    y += height;
  }
  return { blocks, beats, layers, width: maxX, height: Math.max(800, y) };
}
function position(node, rect) { node.style.left = `${rect.x}px`; node.style.top = `${rect.y}px`; node.style.width = `${rect.width}px`; node.style.height = `${rect.height}px`; }
function render() {
  if (!doc) return;
  const g = geometry(), issues = storyIssues(), warning = new Set(issues.map(i => i.id));
  $('layers').replaceChildren(); $('blocks').replaceChildren(); $('links').replaceChildren(); $('snippet-list').replaceChildren(); $('issues').replaceChildren();
  for (const layer of board().layers) {
    const rect = g.layers.get(layer.id), node = element('div', undefined, 'layer'); position(node, { x: 0, y: rect.y, width: g.width, height: rect.height });
    const label = element('button', `${layer.collapsed ? '▸' : '▾'} ${layer.name}`, 'layer-label'); label.onclick = () => edit(() => { layer.collapsed = !layer.collapsed; }); node.append(label); $('layers').append(node);
  }
  for (const block of board().blocks) {
    const rect = g.blocks.get(block.id); if (!rect) continue;
    const node = element('div', undefined, 'block'); position(node, rect);
    const title = element('div', block.name, 'block-title'); node.append(title);
    title.ondblclick = () => { const value = prompt('Block name', block.name); if (value !== null) edit(() => { block.name = value; }); };
    title.onpointerdown = e => {
      if (current.access === 'reader' || locked({ blockID: block.id })) return; e.preventDefault(); title.setPointerCapture(e.pointerId);
      const start = { x: e.clientX, y: e.clientY }, original = clone(block.position);
      title.onpointermove = event => { node.style.left = `${rect.x + event.clientX - start.x}px`; node.style.top = `${rect.y + event.clientY - start.y}px`; };
      title.onpointerup = event => { title.onpointermove = null; title.onpointerup = null; edit(() => { block.position = { x: Math.max(0, original.x + event.clientX - start.x), y: Math.max(32, original.y + event.clientY - start.y) }; }); };
    };
    node.ondragover = e => e.preventDefault(); node.ondrop = e => {
      e.preventDefault(); const id = e.dataTransfer.getData('text/frontstage-beat'), moving = board().beats.find(b => b.id === id); if (!moving || locked(moving) || locked({ blockID: block.id })) return;
      edit(() => { moving.blockID = block.id; moving.order = Math.max(-1, ...board().beats.filter(b => b.blockID === block.id && b.id !== id).map(b => b.order)) + 1; });
    };
    if (!block.collapsed) for (const beat of board().beats.filter(b => b.blockID === block.id).sort((a, b) => a.order - b.order)) {
      const tile = element('div', undefined, `beat${beat.id === selected ? ' selected' : ''}`); tile.style.backgroundColor = /^#[a-f0-9]{6}$/i.test(beat.color) ? beat.color : '#a34eae';
      tile.append(element('span', beat.title, 'beat-text')); tile.draggable = current.access !== 'reader' && !locked(beat);
      if (warning.has(beat.id)) tile.append(element('span', '!', 'badge'));
      tile.onclick = e => { e.stopPropagation(); choose(beat.id); }; tile.ondblclick = () => openEditor(beat.id);
      tile.ondragstart = e => e.dataTransfer.setData('text/frontstage-beat', beat.id);
      node.append(tile);
    }
    $('blocks').append(node);
  }
  $('links').setAttribute('width', g.width); $('links').setAttribute('height', g.height);
  for (const edge of board().dependencies) {
    const a = g.beats.get(edge.cause), b = g.beats.get(edge.effect); if (!a || !b) continue;
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path'), bend = Math.max(35, Math.abs(b.x - a.x - a.width) * .45);
    path.setAttribute('d', `M${a.x + a.width},${a.y + 20} C${a.x + a.width + bend},${a.y + 20} ${b.x - bend},${b.y + 20} ${b.x},${b.y + 20}`);
    path.setAttribute('stroke', edge.cause === selected || edge.effect === selected ? '#8be8f2' : '#d1d1d3'); path.setAttribute('fill', 'none'); if (edge.reference) path.setAttribute('stroke-dasharray', '4 4'); $('links').append(path);
  }
  for (const beat of [...board().beats].sort((a, b) => a.order - b.order)) {
    const card = element('article', undefined, 'snippet-card'); card.append(element('strong', beat.title), element('p', plain(beat.html))); card.onclick = () => { choose(beat.id); openEditor(beat.id); }; $('snippet-list').append(card);
  }
  for (const issue of issues) { const button = element('button', issue.text, 'issue'); button.onclick = () => { if (issue.id) choose(issue.id); }; $('issues').append(button); }
  $('beat-count').textContent = `${board().beats.length} beats`; renderProperties(); renderTimeline();
  document.querySelectorAll('.write').forEach(e => { e.disabled = current.access === 'reader'; });
  const editingBeat = board().beats.find(b => b.id === editorID);
  const textLocked = doc.project.beats.find(s => s.id === editingBeat?.sceneID)?.frontstageTextLocked;
  $('snippet-editor').contentEditable = current.access === 'reader' || textLocked ? 'false' : 'true';
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
  const end = Math.max(20, ...board().beats.map(b => b.start + b.duration)), scale = 22;
  const ruler = element('div', undefined, 'ruler'); ruler.style.width = `${end * scale + 90}px`;
  for (let i = 0; i <= end; i += 5) { const mark = element('span', String(i)); mark.style.left = `${90 + i * scale}px`; ruler.append(mark); }
  const track = element('div', undefined, 'track'), snippets = element('div', undefined, 'track'); track.style.width = ruler.style.width; snippets.style.width = ruler.style.width;
  for (const beat of board().beats) {
    for (const [row, isSnippet] of [[track, false], [snippets, true]]) {
      const tile = element('div', isSnippet ? '' : doc.project.beats.find(s => s.id === beat.sceneID)?.title || beat.title, 'time-beat'); tile.style.left = `${90 + beat.start * scale}px`; tile.style.width = `${Math.max(8, beat.duration * scale - 1)}px`; tile.style.backgroundColor = isSnippet ? beat.color : '#3c65a8'; tile.onclick = () => choose(beat.id); row.append(tile);
    }
  }
  $('timeline').replaceChildren(ruler, track, snippets);
}
function openEditor(id) {
  const beat = board().beats.find(b => b.id === id); if (!beat) return; editorID = id; selected = id;
  $('beat-title').value = beat.title; $('beat-synopsis').value = beat.synopsis; $('beat-kind').value = beat.kind; $('must-cause').checked = beat.mustBeCaused;
  $('beat-characters').value = beat.characters.join(', '); $('beat-tags').value = beat.tags.join(', '); $('snippet-editor').innerHTML = cleanHTML(beat.html); $('editor').hidden = false;
  $('snippet-editor').contentEditable = current.access === 'reader' || doc.project.beats.find(s => s.id === beat.sceneID)?.frontstageTextLocked ? 'false' : 'true';
  $('beat-title').focus();
}
function addBeat() {
  edit(() => {
    const owner = board().beats.find(b => b.id === selected); let blockID = owner?.blockID, sceneID = owner?.sceneID;
    if (!blockID) {
      blockID = uuid(); sceneID = Math.max(0, ...doc.project.beats.map(b => Number(b.id))) + 1;
      doc.project.beats.push({ id: sceneID, title: 'Untitled Scene', content: '', slug: { prefix: 'INT.', location: '', time: 'DAY' }, boardId: 0 }); doc.project.nextId = sceneID + 1;
      board().blocks.push({ id: blockID, name: 'Untitled Block', layerID: board().layers[0].id, position: { x: Math.max(40, $('canvas').scrollLeft + 60), y: 70 }, width: 224, collapsed: false, locked: false });
    }
    const beat = { id: uuid(), sceneID, blockID, title: 'Untitled Beat', synopsis: '', html: '', kind: 'story', color: '#a34eae', characters: [], tags: [], mustBeCaused: false, omitted: false, locked: false, order: Math.max(-1, ...board().beats.map(b => b.order)) + 1, start: Math.max(0, ...board().beats.map(b => b.start + b.duration)), duration: 1.5 };
    board().beats.push(beat); selected = beat.id;
  }); openEditor(selected);
}
function download() { if (!doc) return; const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' }); const link = element('a'); link.href = URL.createObjectURL(blob); link.download = `${doc.name || 'Story'}.frontstage`; link.click(); setTimeout(() => URL.revokeObjectURL(link.href), 1000); }
async function authenticate(signup = false) {
  const form = new FormData($('login')); $('auth-error').textContent = '';
  try { setServer(); const { data } = await api(`/api/${signup ? 'signup' : 'login'}`, 'POST', Object.fromEntries(form)); token = data.token; $('login').reset(); $('server-address').value = apiOrigin; await loadProjects(); status(`Signed in as ${data.username}`); }
  catch (error) { $('auth-error').textContent = error.message; }
}
$('login').onsubmit = e => { e.preventDefault(); authenticate(); }; $('signup').onclick = () => authenticate(true);
$('new-project').onclick = async () => { const name = prompt('Project name', 'Untitled Story'); if (!name) return; try { const document = initializeBoard({ format: 'frontstage', version: 1, name, project: { beats: [], nextId: 1 } }); const { data } = await api('/api/projects', 'POST', { document }); await openProject(data.id); } catch (error) { status(error.message); } };
$('import-project').onchange = async e => { try { const file = e.target.files[0]; if (!file) return; const document = initializeBoard(JSON.parse(await file.text())); const { data } = await api('/api/projects', 'POST', { document }); await openProject(data.id); } catch (error) { status(error.message); } };
$('logout').onclick = async () => { await saveLocal(); ++documentEpoch; clearTimeout(timer); try { await api('/api/logout', 'POST'); } catch {} token = ''; current = null; doc = null; pendingConflict = null; $('conflict').hidden = true; $('workspace').hidden = true; $('projects').hidden = true; $('account').hidden = false; $('editor').hidden = true; status('Signed out · local drafts retained on this device'); };
$('back').onclick = async () => { await saveLocal(); $('editor').hidden = true; editorID = null; loadProjects().catch(e => status(e.message)); };
$('save').onclick = sync; $('download').onclick = download; $('export-conflict').onclick = download;
$('script-toggle').onclick = () => { $('script').hidden = !$('script').hidden; };
$('add-beat').onclick = addBeat; $('add-block').onclick = () => { selected = null; addBeat(); };
$('add-layer').onclick = () => { const name = prompt('Layer name', 'New Layer'); if (name) edit(() => board().layers.push({ id: uuid(), name, height: 300, collapsed: false, locked: false, unused: false })); };
$('cause').onclick = () => { if (selected) { source = selected; status('Select the effect beat'); } };
$('resolve').onclick = () => edit(resolve);
$('fit').onclick = () => { if (!doc) return; const rect = geometry().beats.get(selected); $('canvas').scrollTo({ left: Math.max(0, (rect?.x || 110) - 100), top: Math.max(0, (rect?.y || 60) - 80), behavior: 'smooth' }); };
$('close-editor').onclick = () => { $('editor').hidden = true; editorID = null; };
for (const [id, key] of [['beat-title', 'title'], ['beat-synopsis', 'synopsis'], ['beat-kind', 'kind'], ['must-cause', 'mustBeCaused'], ['beat-characters', 'characters'], ['beat-tags', 'tags']]) {
  $(id).oninput = () => { const beatID = editorID; edit(() => { const beat = board().beats.find(b => b.id === beatID); if (beat) beat[key] = key === 'mustBeCaused' ? $(id).checked : ['characters', 'tags'].includes(key) ? list($(id).value) : $(id).value; }); };
}
$('snippet-editor').oninput = () => { const id = editorID, html = cleanHTML($('snippet-editor').innerHTML); edit(() => { const beat = board().beats.find(b => b.id === id); if (beat) beat.html = html; }); };
$('bold').onclick = () => { $('snippet-editor').focus(); document.execCommand('bold'); }; $('italic').onclick = () => { $('snippet-editor').focus(); document.execCommand('italic'); };
$('element').onchange = () => { const selection = window.getSelection(); let node = selection?.anchorNode?.parentElement; while (node && node.parentElement !== $('snippet-editor') && node !== $('snippet-editor')) node = node.parentElement; if (node && node !== $('snippet-editor')) { node.className = `sc-line sc-${$('element').value}`; $('snippet-editor').dispatchEvent(new Event('input')); } };
$('keep-local').onclick = () => { if (!pendingConflict) return; base = clone(pendingConflict.document); current.revision = pendingConflict.revision; pendingConflict = null; $('conflict').hidden = true; dirty = true; sync(); };
$('take-server').onclick = async () => { if (!pendingConflict) return; download(); doc = initializeBoard(clone(pendingConflict.document)); base = clone(pendingConflict.document); current.revision = pendingConflict.revision; dirty = false; pendingConflict = null; $('conflict').hidden = true; $('editor').hidden = true; editorID = null; await saveLocal(); render(); status('Server copy loaded; previous local copy downloaded'); };
$('share').onclick = async () => { if (!current || current.access !== 'owner') { status('Only the project owner can change access'); return; } const username = prompt('Existing account username'); if (!username) return; const access = prompt('Access: reader or editor', 'editor'); if (!['reader', 'editor'].includes(access)) return; try { await api(`/api/projects/${current.id}/members`, 'POST', { username, access }); status(`Shared with ${username} (${access})`); } catch (error) { status(error.message); } };
document.addEventListener('keydown', e => { if (e.key === 'Escape') { $('editor').hidden = true; editorID = null; source = null; } if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); sync(); } if ((e.ctrlKey || e.metaKey) && e.key === 'z' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName) && !e.target.isContentEditable) { const previous = history.pop(); if (previous) { e.preventDefault(); doc = previous; dirty = true; saveLocal(); render(); } } if (e.key === 'Enter' && e.target === $('canvas') && selected) openEditor(selected); });
window.addEventListener('online', () => { if (dirty) sync(); });
window.addEventListener('beforeunload', e => { if (dirty) { e.preventDefault(); e.returnValue = ''; } });
setInterval(async () => {
  if (!current || !token || dirty || syncing || editorID || pendingConflict) return;
  const epoch = documentEpoch, projectID = current.id;
  try {
    const { data } = await api(`/api/projects/${projectID}`);
    if (epoch !== documentEpoch || current?.id !== projectID || dirty || syncing || editorID || pendingConflict) return;
    if (data.revision !== current.revision) { current = data; base = clone(data.document); doc = initializeBoard(clone(data.document)); render(); await saveLocal(); status(`Updated · revision ${current.revision}`); }
  } catch {}
}, 5000);
