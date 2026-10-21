const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function mergeJSON(base, local, remote) {
  const conflicts = [];
  function merge(b, l, r, path) {
    if (equal(l, r)) return l;
    if (equal(b, l)) return r;
    if (equal(b, r)) return l;
    if (l && r && !Array.isArray(l) && !Array.isArray(r) && typeof l === 'object' && typeof r === 'object') {
      const result = {};
      for (const key of new Set([...Object.keys(b || {}), ...Object.keys(l), ...Object.keys(r)])) {
        const value = merge(b?.[key], l[key], r[key], `${path}/${key.replaceAll('~', '~0').replaceAll('/', '~1')}`);
        if (value !== undefined) Object.defineProperty(result, key, { value, enumerable: true, writable: true, configurable: true });
      }
      return result;
    }
    if (Array.isArray(b) && Array.isArray(l) && Array.isArray(r) && [...b, ...l, ...r].every(v => v && v.id !== undefined)) {
      const map = list => new Map(list.map(v => [String(v.id), v]));
      const bm = map(b), lm = map(l), rm = map(r), values = new Map();
      if (bm.size !== b.length || lm.size !== l.length || rm.size !== r.length) { conflicts.push(path); return l; }
      for (const id of new Set([...bm.keys(), ...lm.keys(), ...rm.keys()])) {
        const value = merge(bm.get(id), lm.get(id), rm.get(id), `${path}/${id}`);
        if (value !== undefined) values.set(id, value);
      }
      const bi = [...bm.keys()], li = [...lm.keys()], ri = [...rm.keys()];
      let order;
      if (equal(li, bi)) order = ri;
      else if (equal(ri, bi) || equal(li, ri)) order = li;
      else {
        const next = new Map(), incoming = new Map([...values.keys()].map(k => [k, 0]));
        for (const list of [li, ri]) {
          const active = list.filter(k => values.has(k));
          for (let i = 1; i < active.length; i++) {
            const a = active[i - 1], c = active[i];
            if (!next.has(a)) next.set(a, new Set());
            if (!next.get(a).has(c)) { next.get(a).add(c); incoming.set(c, incoming.get(c) + 1); }
          }
        }
        order = []; const ready = [...incoming.keys()].filter(k => incoming.get(k) === 0).sort();
        while (ready.length) { const k = ready.shift(); order.push(k); for (const n of next.get(k) || []) { incoming.set(n, incoming.get(n) - 1); if (!incoming.get(n)) { ready.push(n); ready.sort(); } } }
        if (order.length !== values.size) { conflicts.push(`${path}/@order`); order = [...li, ...ri.filter(k => !lm.has(k))]; }
      }
      return order.filter(k => values.has(k)).map(k => values.get(k));
    }
    conflicts.push(path || '/'); return l;
  }
  return { value: merge(base, local, remote, ''), conflicts };
}

function snippetDocument(value) {
  const enclosed = value?.format === 'frontstage', state = enclosed ? value.project : value, board = state?.frontstageWhiteboard;
  if (!board || board.version !== 1 || !Array.isArray(state.beats) || !['layers', 'blocks', 'beats', 'dependencies'].every(k => Array.isArray(board[k]))) return null;
  const unique = rows => rows.every(r => r && typeof r.id === 'string' && r.id) && new Set(rows.map(r => r.id)).size === rows.length;
  if (!['layers', 'blocks', 'beats', 'dependencies'].every(k => unique(board[k])) || !board.layers.length || !state.beats.every(s => s && Number.isSafeInteger(s.id) && s.id >= 0) || new Set(state.beats.map(s => s.id)).size !== state.beats.length) return null;
  const scenes = new Map(state.beats.map(s => [s.id, s])), layers = new Map(board.layers.map(l => [l.id, l])), blocks = new Map(board.blocks.map(b => [b.id, b])), ids = new Set(board.beats.map(b => b.id));
  for (const block of board.blocks) {
    if (!layers.has(block.layerID) || (block.parentID && !blocks.has(block.parentID))) return null;
    const seen = new Set([block.id]);
    for (let parent = block.parentID; parent; parent = blocks.get(parent)?.parentID) { if (seen.has(parent)) return null; seen.add(parent); }
  }
  if (board.beats.some(b => !scenes.has(b.sceneID) || !blocks.has(b.blockID) || typeof b.html !== 'string' || !Array.isArray(b.characters) || b.characters.some(c => typeof c !== 'string') || !Number.isFinite(b.order) || !Number.isFinite(b.start) || b.start < 0 || !Number.isFinite(b.duration) || b.duration < .05 || b.duration > 1000)) return null;
  if (board.dependencies.some(e => !ids.has(e.cause) || !ids.has(e.effect) || e.cause === e.effect)) return null;
  const projections = new Map();
  for (const beat of [...board.beats].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id))) {
    if (!projections.has(beat.sceneID)) projections.set(beat.sceneID, { html: '', characters: [], disabled: true });
    if (beat.omitted || layers.get(blocks.get(beat.blockID).layerID).unused) continue;
    const p = projections.get(beat.sceneID); p.html += beat.html; p.characters.push(...beat.characters); p.disabled = false;
  }
  for (const p of projections.values()) p.characters = [...new Set(p.characters)].sort();
  return { value, state, enclosed, scenes, projections };
}
function canonical(shape, id) {
  const scene = shape.scenes.get(id), p = shape.projections.get(id);
  if (!scene || !p || scene.content !== p.html || !!scene.isDisabled !== p.disabled) return false;
  if (scene.characters === undefined) return !p.characters.length;
  return Array.isArray(scene.characters) && scene.characters.every(c => typeof c === 'string') && equal([...new Set(scene.characters)].sort(), p.characters);
}
function normalized(shape, ids) {
  const value = structuredClone(shape.value), state = shape.enclosed ? value.project : value;
  for (const scene of state.beats) if (ids.has(scene.id)) { delete scene.content; delete scene.characters; delete scene.isDisabled; }
  return value;
}
export function mergeDocuments(base, local, remote) {
  const shapes = [base, local, remote].map(snippetDocument), prefix = local?.format === 'frontstage' ? '/project' : '';
  if (shapes.some(s => !s) || shapes.some(s => s.enclosed !== shapes[0].enclosed)) {
    const result = mergeJSON(base, local, remote), state = result.value?.format === 'frontstage' ? result.value.project : result.value;
    if (state?.frontstageWhiteboard && !snippetDocument(result.value)) return { value: local, conflicts: [...new Set([...result.conflicts, prefix + '/frontstageWhiteboard'])].sort() };
    const shape = snippetDocument(result.value);
    if (shape) {
      const inconsistent = [...shape.projections.keys()].filter(id => !canonical(shape, id));
      if (inconsistent.length) return { value: local, conflicts: [...new Set([...result.conflicts, ...inconsistent.map(id => `${prefix}/beats/${id}/content`)])].sort() };
    }
    return result;
  }
  const ids = new Set([...shapes[0].projections.keys()].filter(id => shapes.every(s => canonical(s, id))));
  const result = mergeJSON(...shapes.map(s => normalized(s, ids))), merged = snippetDocument(result.value);
  if (!merged) return { value: local, conflicts: [...new Set([...result.conflicts, prefix + '/frontstageWhiteboard'])].sort() };
  const value = structuredClone(result.value), state = merged.enclosed ? value.project : value;
  for (const scene of state.beats) if (ids.has(scene.id)) {
    const p = merged.projections.get(scene.id) || { html: '', characters: [], disabled: true };
    if (scene.frontstageTextLocked && !shapes.some(s => s.scenes.get(scene.id)?.frontstageTextLocked && s.projections.get(scene.id)?.html === p.html)) result.conflicts.push(`${prefix}/beats/${scene.id}/content`);
    scene.content = p.html; scene.characters = p.characters; scene.isDisabled = p.disabled;
  }
  return { value, conflicts: [...new Set(result.conflicts)].sort() };
}
