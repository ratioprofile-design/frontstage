import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {reconcileScriptAnnotations,annotationIDs,annotationFreeComparisonHTML} from '../Public/script-annotations.js';
import {duplicateBeat} from '../Public/scene-model.js';
import {insertScriptScene} from '../Public/continuous-script.js';
import {requiredWriteFeatures,validateServerFeatures} from '../Public/feature-compatibility.js';
globalThis.crypto ||= webcrypto;
const d=JSON.parse(await readFile(new URL('../../Tests/Fixtures/write-panels.frontstage',import.meta.url))),scene=d.project.beats[0],beat=d.project.frontstageWhiteboard.beats.find(b=>b.sceneID===scene.id);
scene.breakdownData={VEHICLES:[{id:'linked-1',name:'red car',sourceQuote:'red car',category:'VEHICLES',future:{keep:true},frontstageSourceLinked:true}]};
beat.html='<p>Before.</p><p><span data-dot-breakdown="linked-1" data-dot-category="VEHICLES"><span data-dot-highlight="Yellow">red car</span></span></p>';scene.content=beat.html;
const copyID=duplicateBeat(d,beat.id),copy=d.project.frontstageWhiteboard.beats.find(b=>b.id===copyID),copyScene=d.project.beats.find(s=>s.id===copy.sceneID),copied=copyScene.breakdownData.VEHICLES[0];assert.notEqual(copied.id,'linked-1');assert.deepEqual(annotationIDs(copy.html),[copied.id]);assert.deepEqual(copied.future,{keep:true});
const nextID=insertScriptScene(d,beat.id,'<p>Before.</p>','<p><span data-dot-breakdown="linked-1">red car</span></p>','EXT. ROAD - DAY'),next=d.project.frontstageWhiteboard.beats.find(b=>b.id===nextID),nextScene=d.project.beats.find(s=>s.id===next.sceneID);assert.equal(scene.breakdownData.VEHICLES.length,0);assert.equal(nextScene.breakdownData.VEHICLES[0].id,'linked-1');assert.match(next.html,/data-dot-category="VEHICLES"/);
nextScene.breakdownData.VEHICLES[0].category='PROPS';reconcileScriptAnnotations(d);assert.match(next.html,/data-dot-category="PROPS"/);nextScene.breakdownData.VEHICLES=[];reconcileScriptAnnotations(d);assert.deepEqual(annotationIDs(next.html),[]);assert.match(next.html,/red car/);
assert.ok(requiredWriteFeatures(d).includes('scriptAnnotations'));assert.throws(()=>validateServerFeatures(d,['elementTypography','dualDialogue','productionBaselines']),/Update/);
console.log('PASS: annotation ownership, split, duplicate IDs, unknown metadata, category changes, deletion and compatibility');

assert.equal(annotationFreeComparisonHTML('<p>A <span data-dot-highlight="Blue"><span data-dot-breakdown="r-1">red car</span></span>.</p>'),'<p>A red car.</p>');
