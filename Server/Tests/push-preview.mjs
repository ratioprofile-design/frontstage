import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {previewBoardPush} from '../Public/board-operations.js';
const doc=JSON.parse(await readFile(new URL('../../Tests/Fixtures/write-panels.frontstage',import.meta.url))),source=doc.project.frontstageWhiteboard;
source.blocks=source.blocks.slice(0,2);source.blocks.forEach((b,i)=>{b.position={x:i?300:50,y:20};b.width=140;delete b.parentID;});source.beats=source.beats.filter(b=>source.blocks.some(c=>c.id===b.blockID));source.beats.forEach((b,i)=>{b.order=1-i;b.locked=false;});source.dependencies=[];
const before=structuredClone(source),cases=JSON.parse(await readFile(new URL('../../Tests/Fixtures/push-preview.json',import.meta.url)));
for(const item of cases){const result=previewBoardPush(source,200,item.distance);assert.deepEqual(result.blocks[0].position,{x:50,y:20});assert.deepEqual(result.blocks[1].position,{x:item.rightX,y:20});assert.deepEqual(source,before);}
assert.deepEqual(previewBoardPush(source,900,50),source);assert.deepEqual(previewBoardPush(source,200,4),source);assert.throws(()=>previewBoardPush(source,NaN,10));assert.throws(()=>previewBoardPush(source,200,Infinity));source.beats[1].locked=true;const locked=structuredClone(source);assert.throws(()=>previewBoardPush(source,200,20));assert.deepEqual(source,locked);console.log('PASS: detached Push preview, exact packing gap, symmetric snapping, preserved vertical position, no-op and atomic locks');
