import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dependencyRoute,editDependency} from '../Public/board-operations.js';
for(const end of [{x:600,y:380,width:140,height:80},{x:30,y:450,width:100,height:40}]){
 const route=dependencyRoute({x:100,y:80,width:150,height:40},end);
 for(const zoom of [.15,1,3]){for(const t of [0,.1,.5,.9,1])assert.ok(route.contains(route.point(t),6/zoom));assert.equal(route.contains({x:1000,y:1000},6/zoom),false);}
 assert.equal(route.contains({x:NaN,y:0},6),false);
}
const board=JSON.parse(await readFile(new URL('../../Tests/Fixtures/write-panels.frontstage',import.meta.url),'utf8')).project.frontstageWhiteboard;
board.dependencies=[{id:'forward',cause:'beat-1',effect:'beat-2',reference:false,reason:''},{id:'back',cause:'beat-2',effect:'beat-1',reference:true,reason:''}];
const before=structuredClone(board),updated=editDependency(board,'forward',{reason:'Because they met'});assert.equal(updated.dependencies[0].reason,'Because they met');assert.deepEqual(board,before);assert.deepEqual(updated.beats,board.beats);
assert.throws(()=>editDependency(board,'back',{reference:false}),/loop/i);assert.deepEqual(board,before);
board.beats[1].locked=true;assert.throws(()=>editDependency(board,'forward',{remove:true}),/Unlock/);assert.throws(()=>editDependency(board,'forward',{reason:'Changed'}),/Unlock/);board.beats[1].locked=false;
assert.deepEqual(editDependency(board,'forward',{remove:true}).dependencies.map(e=>e.id),['back']);console.log('PASS: dependency curve picking, detached edits, locked endpoints and cycle rollback');
