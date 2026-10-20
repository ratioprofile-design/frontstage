const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function mergeDocuments(base, local, remote) {
  const conflicts = [];
  function merge(b, l, r, path) {
    if (equal(l, r)) return l;
    if (equal(b, l)) return r;
    if (equal(b, r)) return l;
    if (l && r && !Array.isArray(l) && !Array.isArray(r) && typeof l === 'object' && typeof r === 'object') {
      const result = {};
      for (const key of new Set([...Object.keys(b || {}), ...Object.keys(l), ...Object.keys(r)])) {
        const value = merge(b?.[key], l[key], r[key], `${path}/${key}`);
        if (value !== undefined) result[key] = value;
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
