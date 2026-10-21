// Portable browser operations mirror the native document rules. Return copies so failures are atomic.
const copy = value => structuredClone(value);
export function validateBoard(board, sceneIDs) {
  const fail = () => { throw Error('The whiteboard contains invalid identifiers, geometry or references.'); };
  const coordinate = n => Number.isFinite(n) && Math.abs(n) <= 1000000;
  const unique = rows => Array.isArray(rows) && rows.every(r => r && typeof r.id === 'string' && r.id) && new Set(rows.map(r => r.id)).size === rows.length;
  const strings = rows => Array.isArray(rows) && rows.every(s => typeof s === 'string');
  if (board?.version !== 1 || !['layers', 'blocks', 'beats', 'dependencies', 'strokes'].every(k => unique(board[k])) || !board.layers.length || !coordinate(board.viewport?.origin?.x) || !coordinate(board.viewport?.origin?.y) || !Number.isFinite(board.viewport?.zoom) || board.viewport.zoom < .15 || board.viewport.zoom > 3) fail();
  const layers = new Set(board.layers.map(l => l.id)), blocks = new Map(board.blocks.map(b => [b.id, b])), beats = new Set(board.beats.map(b => b.id));
  for (const layer of board.layers) if (typeof layer.name !== 'string' || !Number.isFinite(layer.height) || layer.height < 100 || layer.height > 10000 || !['locked', 'collapsed', 'unused'].every(k => typeof layer[k] === 'boolean')) fail();
  for (const block of board.blocks) {
    if (!layers.has(block.layerID) || typeof block.name !== 'string' || !coordinate(block.position?.x) || !coordinate(block.position?.y) || !Number.isFinite(block.width) || block.width < 140 || block.width > 2000 || !['locked', 'collapsed'].every(k => typeof block[k] === 'boolean') || (block.parentID != null && !blocks.has(block.parentID))) fail();
    const seen = new Set([block.id]);
    for (let parent = block.parentID; parent != null; parent = blocks.get(parent)?.parentID) { if (seen.has(parent)) fail(); seen.add(parent); }
  }
  for (const beat of board.beats) if (!sceneIDs.has(beat.sceneID) || !blocks.has(beat.blockID) || !coordinate(beat.order) || !coordinate(beat.start) || beat.start < 0 || !Number.isFinite(beat.duration) || beat.duration < .05 || beat.duration > 1000 || !['title', 'synopsis', 'html', 'color'].every(k => typeof beat[k] === 'string') || !['story', 'subtext'].includes(beat.kind) || !strings(beat.characters) || !strings(beat.tags) || !['mustBeCaused', 'omitted', 'locked'].every(k => typeof beat[k] === 'boolean')) fail();
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
export function moveBlocks(source, ids, dx, dy) {
  const board = copy(source), moving = descendantBlocks(board, ids), items = board.blocks.filter(b => moving.has(b.id)), locked = lockedBlockIDs(board);
  if (!ids.size || !Number.isFinite(dx) || !Number.isFinite(dy) || items.length !== moving.size || items.some(b => locked.has(b.id))) throw Error('Select unlocked blocks to move.');
  dx = Math.max(dx, -Math.min(...items.map(b => b.position.x))); dy = Math.max(dy, 32 - Math.min(...items.map(b => b.position.y)));
  for (const block of items) {
    block.position.x += dx; block.position.y += dy;
    if (Math.abs(block.position.x) > 1000000 || Math.abs(block.position.y) > 1000000) throw Error('Board position is out of range.');
  }
  return board;
}
export function groupBlocks(source, ids, name, id) {
  const board = copy(source), items = board.blocks.filter(b => ids.has(b.id));
  if (items.length !== ids.size || items.length < 2 || items.some(b => blockLocked(board, b.id)) || new Set(items.map(b => b.layerID)).size !== 1 || items.some(b => b.parentID !== items[0].parentID)) throw Error('Select at least two unlocked blocks with the same layer and parent.');
  if (!id || board.blocks.some(b => b.id === id)) throw Error('Invalid new group identifier.');
  const position = { x: Math.max(0, Math.min(...items.map(b => b.position.x)) - 18), y: Math.max(32, Math.min(...items.map(b => b.position.y)) - 28) };
  const group = { id, name, layerID: items[0].layerID, position, width: Math.min(2000, Math.max(224, Math.max(...items.map(b => b.position.x + b.width)) - position.x + 18)), collapsed: false, locked: false };
  if (items[0].parentID) group.parentID = items[0].parentID;
  items.forEach(b => { b.parentID = id; }); board.blocks.push(group); return board;
}
export function ungroupBlocks(source, ids) {
  const board = copy(source), groups = board.blocks.filter(b => ids.has(b.id)), byID = new Map(board.blocks.map(b => [b.id, b]));
  if (!ids.size || groups.length !== ids.size || groups.some(g => blockLocked(board, g.id) || !board.blocks.some(b => b.parentID === g.id))) throw Error('Select unlocked groups to ungroup.');
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
