import assert from 'node:assert/strict';
import {deleteBeats} from '../Public/board-operations.js';
const document={project:{beats:[{id:1,content:'a'},{id:2,content:'b'}],frontstageWhiteboard:{layers:[{id:'main',locked:false}],blocks:[{id:'manual',layerID:'main'},{id:'group',layerID:'main',containerKind:'beatGroup',parentID:'manual'},{id:'loose',layerID:'main',standalone:true},{id:'empty',layerID:'main',containerKind:'beatGroup'}],beats:[{id:'a',sceneID:1,blockID:'group'},{id:'b',sceneID:1,blockID:'group'},{id:'c',sceneID:2,blockID:'loose'}],dependencies:[{id:'link',cause:'a',effect:'c'}]}}};
const original=structuredClone(document),loose=deleteBeats(document,new Set(['c']));assert.ok(!loose.project.frontstageWhiteboard.blocks.some(b=>b.id==='loose'));assert.equal(loose.project.frontstageWhiteboard.dependencies.length,0);assert.deepEqual(document,original);
const first=deleteBeats(document,new Set(['a']));assert.ok(first.project.frontstageWhiteboard.blocks.some(b=>b.id==='group'));
const last=deleteBeats(first,new Set(['b']));assert.deepEqual(last.project.frontstageWhiteboard.blocks.map(b=>b.id),['manual','loose','empty']);assert.equal(last.project.beats[0].content,'');
const locked=structuredClone(document);locked.project.frontstageWhiteboard.blocks[0].locked=true;assert.throws(()=>deleteBeats(locked,new Set(['a','c'])));assert.equal(locked.project.frontstageWhiteboard.beats.length,3);
console.log('PASS: beat deletion prunes loose containers and emptied groups, preserves explicit blocks/unrelated groups, removes links and rejects locked selections atomically');
