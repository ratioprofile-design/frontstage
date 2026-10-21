import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { writeFile, readFile } from 'node:fs/promises';
import * as m from '../Public/workspace-model.js';
import { validateBoard } from '../Public/board-operations.js';
globalThis.crypto ||= webcrypto;
const doc={format:'frontstage',version:1,name:'The Invitation',project:{nextId:3,customFuture:{preserve:true},beats:[{id:1,title:'The Invitation',content:'<p class="sc-action">தமிழ் — an invitation arrives.</p>',summary:'The story begins',slug:{prefix:'INT.',location:'STATION',time:'DAY'},characters:[]},{id:2,title:'The Decision',content:'<p class="sc-character">MAYA</p><p class="sc-dialogue">I will go.</p>',slug:{prefix:'EXT.',location:'PLATFORM',time:'NIGHT'},characters:[]}],frontstageWhiteboard:{version:1,viewport:{origin:{x:0,y:0},zoom:1},layers:[{id:'main',name:'Main Layer',height:300,collapsed:false,locked:false,unused:false}],blocks:[],beats:[],dependencies:[],strokes:[]}}};
for(const s of doc.project.beats){const id=`block-${s.id}`;doc.project.frontstageWhiteboard.blocks.push({id,name:s.title,layerID:'main',position:{x:70+(s.id-1)*290,y:70},width:224,collapsed:false,locked:false,standalone:s.id===2});doc.project.frontstageWhiteboard.beats.push({id:`beat-${s.id}`,sceneID:s.id,blockID:id,title:s.title,synopsis:s.summary||'',html:s.content,kind:'story',color:s.id===1?'#39798c':'#a34eae',characters:[],tags:[],mustBeCaused:s.id===2,omitted:false,locked:false,order:s.id-1,start:(s.id-1)*3,duration:2});}
doc.project.frontstageWhiteboard.dependencies.push({id:'cause-1',cause:'beat-1',effect:'beat-2',reason:'The invitation forces a decision',reference:false});
const role=m.createCharacter(doc,'Maya');assert.equal(role,'MAYA');assert.throws(()=>m.createCharacter(doc,'maya'));
m.assignCharacter(doc,2,role,true);assert.deepEqual(doc.project.frontstageWhiteboard.beats[1].characters,['MAYA']);
const actor=m.addActor(doc,role,'Anika');m.confirmActor(doc,role,actor);doc.project.characterData[role].artists[0].contact={email:'anika@example.test',phone:'555-0100'};
m.addRequirement(doc,1,'PROPS','Invitation',2,'Sealed envelope');
const rev=m.captureRevision(doc,1,'Before the reply');assert.equal(doc.project.beats[0].versions[0].frontstageSnippets[0].html,doc.project.beats[0].content);
const changed=structuredClone(doc);changed.project.frontstageWhiteboard.beats[0].html='<p>Changed.</p>';changed.project.beats[0].content='<p>Changed.</p>';m.restoreRevision(changed,1,rev);assert.equal(changed.project.frontstageWhiteboard.beats.find(b=>b.id==='beat-1').html,doc.project.beats[0].content);assert.equal(changed.project.beats[0].versions.length,2);
const locked=structuredClone(doc);locked.project.beats[0].frontstageTextLocked=true;assert.throws(()=>m.restoreRevision(locked,1,rev));
const day=m.addDay(doc,'2026-10-22');m.assignDay(doc,1,day);m.assignDay(doc,2,day);doc.project.frontstageProduction.days[0].locationName='Station';doc.project.frontstageProduction.days[0].castCalls.MAYA={onSetTime:'07:00',notes:'Platform entrance'};
const record=m.addRecord(doc,'research',1);doc.project.frontstageStudio.records[0].title='Station reference';doc.project.frontstageStudio.records[0].body='Keep the original invitation.';m.addAttachment(doc,record,'reference.txt',Buffer.from('Reference text').toString('base64'));
m.setTypography(doc,{fontName:'Courier',fontSize:12,lineHeight:14,paragraphSpacing:10});doc.project.beats[0].frontstageParallel=[{id:'parallel-1',left:'The invitation',right:'அழைப்பு'}];
validateBoard(doc.project.frontstageWhiteboard,new Set([1,2]));assert.deepEqual(m.scriptSegments(doc).map(s=>s.scene.id),[1,2]);
const split=structuredClone(doc);const id=m.splitBeat(split,'beat-1','<p>First</p>','<p>Second</p>');assert.equal(split.project.frontstageWhiteboard.dependencies[0].cause,id);assert.equal(m.scriptSegments(split)[0].html,'<p>First</p><p>Second</p>');
assert.deepEqual(doc.project.customFuture,{preserve:true});
const fixture=new URL('../../Tests/Fixtures/workspace-parity.frontstage',import.meta.url);
if(process.argv.includes('--write-fixture'))await writeFile(fixture,JSON.stringify(doc,null,2)+'\n');
else {const saved=JSON.parse(await readFile(fixture,'utf8'));validateBoard(saved.project.frontstageWhiteboard,new Set([1,2]));assert.equal(saved.project.characterData.MAYA.name,'MAYA');}
console.log('PASS: workspace models preserve native character/casting, breakdown, revision, production, media, script and unknown-field data');
