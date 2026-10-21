import assert from 'node:assert/strict';
import { groupBlocks, ungroupBlocks, moveBlocks, compactCausalTime, deleteBlocks, validateBoard } from '../Public/board-operations.js';
const board = { version: 1, layers: [{ id: 'main', unused: false }], blocks: [
  { id: 'a', layerID: 'main', position: { x: 40, y: 50 }, width: 224 }, { id: 'b', layerID: 'main', position: { x: 280, y: 90 }, width: 224 }
], beats: [
  { id: 'first', sceneID: 1, blockID: 'a', title: 'First', start: 10, duration: 2, order: 0, html: '<p>தமிழ்</p>' },
  { id: 'second', sceneID: 2, blockID: 'b', title: 'Second', start: 50, duration: 1, order: 1 }
], dependencies: [{ id: 'edge', cause: 'first', effect: 'second' }] };
const grouped = groupBlocks(board, new Set(['a', 'b']), 'Act I', 'group');
assert.equal(board.blocks.length, 2);
const moved = moveBlocks(grouped, new Set(['group']), -1000, -1000);
assert.equal(moved.blocks[1].position.x - moved.blocks[0].position.x, 240);
assert.equal(moved.blocks[1].position.y - moved.blocks[0].position.y, 40);
const ungrouped = ungroupBlocks(moved, new Set(['group']));
assert.equal(ungrouped.blocks.length, 2); assert.ok(ungrouped.blocks.every(b => b.parentID === undefined));
assert.deepEqual(ungrouped.beats, board.beats); assert.deepEqual(ungrouped.dependencies, board.dependencies);
const compacted = compactCausalTime(board);
assert.equal(compacted.beats[0].start, 0); assert.equal(compacted.beats[1].start, 2);
assert.deepEqual(compacted.blocks, board.blocks);
const locked = structuredClone(grouped); locked.blocks[0].locked = true;
assert.throws(() => ungroupBlocks(locked, new Set(['group'])));
assert.throws(() => moveBlocks(locked, new Set(['group']), 10, 10));
const doc = { project: { beats: [{ id: 1, content: '<p>தமிழ்</p>', future: 42 }, { id: 2, content: '' }], frontstageWhiteboard: grouped } };
const deleted = deleteBlocks(doc, new Set(['group']));
assert.equal(deleted.project.frontstageWhiteboard.blocks.length, 0); assert.equal(deleted.project.frontstageWhiteboard.dependencies.length, 0);
assert.ok(deleted.project.beats.every(s => s.isDisabled && s.content === '')); assert.equal(deleted.project.beats[0].future, 42);
doc.project.beats[0].frontstageTextLocked = true;
assert.throws(() => deleteBlocks(doc, new Set(['group']))); assert.equal(doc.project.frontstageWhiteboard.blocks.length, 3);
const blocked = structuredClone(board); blocked.beats[0].locked = true; blocked.beats[1].start = 0; blocked.beats[1].locked = true;
assert.throws(() => compactCausalTime(blocked)); assert.equal(blocked.beats[0].start, 10);
console.log('PASS: browser grouping/ungrouping, rigid movement, compaction, protected deletion and failure rollback');
const valid = { ...structuredClone(board), viewport: { origin: { x: 0, y: 0 }, zoom: 1 }, strokes: [] };
valid.layers = [{ id: 'main', name: 'Main', height: 300, unused: false, locked: false, collapsed: false }];
valid.blocks = valid.blocks.map(b => ({ ...b, name: 'Block', locked: false, collapsed: false }));
valid.beats = valid.beats.map(b => ({ ...b, html: b.html || '', synopsis: '', color: '#39798c', kind: 'story', characters: [], tags: [], mustBeCaused: false, omitted: false, locked: false }));
valid.dependencies = valid.dependencies.map(e => ({ ...e, reason: '', reference: false }));
validateBoard(valid, new Set([1, 2]));
const invalid = structuredClone(valid); invalid.blocks[0].parentID = 'b'; invalid.blocks[1].parentID = 'a';
assert.throws(() => validateBoard(invalid, new Set([1, 2])));
assert.throws(() => validateBoard(valid, new Set([1])));
const causalLoop = structuredClone(valid); causalLoop.dependencies.push({ id: 'reverse', cause: 'second', effect: 'first', reference: false, reason: '' });
validateBoard(causalLoop, new Set([1, 2])); // Imported causal loops remain diagnosable instead of being silently deleted.
console.log('PASS: browser import rejects malformed/cyclic containers and missing references while retaining diagnosable causal cycles');
