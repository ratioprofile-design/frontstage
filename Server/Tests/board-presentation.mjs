import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {boardFlowLines,boardTrackNames} from '../Public/board-operations.js';
import {timelineColor} from '../Public/story-timeline.js';
const {board,expected}=JSON.parse(await readFile(new URL('../../Tests/Fixtures/board-presentation.json',import.meta.url),'utf8')),before=structuredClone(board),beat=board.beats[0];
assert.deepEqual(boardTrackNames(beat,'characters'),expected.names);assert.deepEqual(boardTrackNames(beat,'characters').map(timelineColor),expected.colors);
assert.deepEqual(boardTrackNames(beat,'tags'),['Hope']);assert.deepEqual(boardFlowLines(board,'tags','Hope').map(e=>[e.cause,e.effect]),expected.lines);assert.deepEqual(boardFlowLines(board,'characters','MAYA').map(e=>[e.cause,e.effect]),expected.lines);assert.deepEqual(boardFlowLines(board,'bad','Hope'),[]);assert.deepEqual(boardFlowLines(board,'tags','Missing'),[]);assert.deepEqual(board,before);
assert.deepEqual(boardTrackNames({...beat,characters:['E\u0301','É',' É ']},'characters'),['É']);
console.log('PASS: shared FlowLines exclude inactive beats, retain narrative order and never mutate authored colors or dependencies');
