import assert from 'node:assert/strict';
import { mergeDocuments, mergeJSON } from '../Public/merge.js';
const base = { beats: [{ id: 'a', title: 'Original', x: 0, future: true }] };
const local = structuredClone(base); local.beats[0].title = 'Edited';
const remote = structuredClone(base); remote.beats[0].x = 50;
const result = mergeDocuments(base, local, remote);
assert.deepEqual(result.conflicts, []);
assert.deepEqual(result.value.beats[0], { id: 'a', title: 'Edited', x: 50, future: true });
remote.beats[0].title = 'Remote';
assert.deepEqual(mergeDocuments(base, local, remote).conflicts, ['/beats/a/title']);
assert.deepEqual(mergeDocuments(base, { beats: [] }, remote).conflicts, ['/beats/a']);
assert.equal(mergeDocuments([{ id: 'a' }, { id: 'z' }], [{ id: 'a' }, { id: 'b' }, { id: 'z' }], [{ id: 'a' }, { id: 'c' }, { id: 'z' }]).value.length, 4);
console.log('PASS: browser merge preserves independent fields, detects edit/delete conflicts and combines independent insertions');

const document = { format: 'frontstage', version: 1, name: 'Two snippets', project: {
  beats: [{ id: 1, title: 'Scene', content: '<p>A</p><p>B</p>', characters: [], isDisabled: false, future: 42 }],
  frontstageWhiteboard: { version: 1, layers: [{ id: 'main' }], blocks: [{ id: 'block', layerID: 'main' }],
    beats: [
      { id: 'a', sceneID: 1, blockID: 'block', order: 0, start: 0, duration: 1, html: '<p>A</p>', characters: [] },
      { id: 'b', sceneID: 1, blockID: 'block', order: 1, start: 1, duration: 1, html: '<p>B</p>', characters: [] }
    ], dependencies: [] }
} };
const left = structuredClone(document), right = structuredClone(document);
left.project.frontstageWhiteboard.beats[0].html = '<p>தமிழ் local</p>'; left.project.frontstageWhiteboard.beats[0].characters = ['Mara'];
left.project.beats[0].content = '<p>தமிழ் local</p><p>B</p>'; left.project.beats[0].characters = ['Mara'];
right.project.frontstageWhiteboard.beats[1].html = '<p>Remote</p>'; right.project.frontstageWhiteboard.beats[1].characters = ['Jon'];
right.project.beats[0].content = '<p>A</p><p>Remote</p>'; right.project.beats[0].characters = ['Jon'];
assert.ok(mergeJSON(document, left, right).conflicts.length);
const merged = mergeDocuments(document, left, right);
assert.deepEqual(merged.conflicts, []);
assert.equal(merged.value.project.beats[0].content, '<p>தமிழ் local</p><p>Remote</p>');
assert.deepEqual(merged.value.project.beats[0].characters, ['Jon', 'Mara']);
assert.equal(merged.value.project.beats[0].future, 42);
assert.equal(document.project.beats[0].content, '<p>A</p><p>B</p>');
const locked = structuredClone(document); locked.project.beats[0].frontstageTextLocked = true;
assert.ok(mergeDocuments(document, left, locked).conflicts.includes('/project/beats/1/content'));
const imported = structuredClone(left); imported.project.beats[0].content = '<p>Unprojected imported text</p>';
assert.ok(mergeDocuments(document, imported, right).conflicts.includes('/project/beats/1/content'));
const same = structuredClone(left); same.project.frontstageWhiteboard.beats[0].html = '<p>Other edit</p>'; same.project.beats[0].content = '<p>Other edit</p><p>B</p>';
assert.ok(mergeDocuments(document, left, same).conflicts.some(path => path.endsWith('/html')));
const oddBase = JSON.parse('{"__proto__":{"kept":1},"a/b":0}'), oddLocal = JSON.parse('{"__proto__":{"kept":2},"a/b":1}'), oddRemote = JSON.parse('{"__proto__":{"kept":1},"a/b":2}');
const odd = mergeJSON(oddBase, oddLocal, oddRemote);
assert.ok(Object.hasOwn(odd.value, '__proto__')); assert.equal(odd.value.__proto__.kept, 2); assert.equal(Object.prototype.kept, undefined);
assert.deepEqual(odd.conflicts, ['/a~1b']);
console.log('PASS: canonical snippet merge rebuilds scene text/roles, retains genuine text/lock/import conflicts and preserves unusual metadata keys');
