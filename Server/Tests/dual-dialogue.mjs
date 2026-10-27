import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {pairDialogueHTML,removeDualDialogueHTML,dialoguePairs,dialoguePairHTML,pairDialogue,removeDualDialogue} from '../Public/dual-dialogue.js';

const fixtures=JSON.parse(await readFile(new URL('../../Tests/Fixtures/dual-dialogue.json',import.meta.url),'utf8'));
for(const example of fixtures.valid){
  const paired=pairDialogueHTML(example.html,example.first,example.second);
  assert.deepEqual(dialoguePairs(paired),[{left:example.left,right:example.right}],example.name);
  assert.ok(paired.includes(dialoguePairHTML(example.left,example.right)),example.name);
  assert.equal(removeDualDialogueHTML(paired,example.pairIndex),example.html,example.name);
  assert.throws(()=>pairDialogueHTML(paired,example.pairIndex,example.pairIndex+1),undefined,example.name);
  const saved=JSON.parse(JSON.stringify({html:paired,future:{preserve:true}}));
  assert.deepEqual(dialoguePairs(saved.html),[{left:example.left,right:example.right}]);
  assert.deepEqual(saved.future,{preserve:true});
}
for(const example of fixtures.invalid)assert.throws(()=>pairDialogueHTML(example.html,example.first,example.second),undefined,example.name);
for(const index of [-1,0.5,NaN,Infinity,20])assert.throws(()=>pairDialogueHTML(fixtures.valid[0].html,index,2));
assert.throws(()=>removeDualDialogueHTML('<p>Normal text</p>',0));
assert.throws(()=>dialoguePairs("<div class='sc-dual'><div class='sc-dual-column sc-dual-left'>Missing right column</div></div>"));
const first=fixtures.valid[0],single=pairDialogueHTML(first.html,0,2);
const annotated=single.replace('</div><div class="sc-dual-column sc-dual-right">','</div>\n<!-- imported reference -->\n<div class="sc-dual-column sc-dual-right">');
assert.equal(removeDualDialogueHTML(annotated,0),first.left+'\n<!-- imported reference -->\n'+first.right);
const double=pairDialogueHTML(pairDialogueHTML(first.html+first.html,0,2),1,3);
assert.equal(dialoguePairs(double).length,2);
assert.equal(removeDualDialogueHTML(removeDualDialogueHTML(double,1),0),first.html+first.html);
const html=fixtures.valid[0].html;
const document={format:'frontstage',version:1,name:'Dialogue',project:{frontstageSceneModel:'oneBeatPerScene',future:{preserve:true},beats:[{id:1,title:'Overlap',summary:'Keep this',content:html,notes:[{id:'note',content:'Keep **this**',color:'#fff4bc',future:42}],breakdown:{PROPS:[{id:'prop',name:'Phone'}]},versions:[]}],frontstageWhiteboard:{version:1,viewport:{origin:{x:0,y:0},zoom:1},layers:[{id:'main',name:'Main',height:300,collapsed:false,locked:false,unused:false}],blocks:[{id:'block',name:'Block',layerID:'main',position:{x:70,y:70},width:224,collapsed:false,locked:false,standalone:true}],beats:[{id:'beat',sceneID:1,blockID:'block',title:'Overlap',synopsis:'Keep this',html,kind:'story',color:'#a34eae',characters:[],tags:[],mustBeCaused:false,omitted:false,locked:false,order:0,start:0,duration:2,future:'preserved'}],dependencies:[],strokes:[]}}};
const original=structuredClone(document),paired=pairDialogue(document,'beat',0,2);
assert.deepEqual(document,original,'Pairing returns a candidate without mutating the workspace');
assert.equal(paired.project.beats[0].content,paired.project.frontstageWhiteboard.beats[0].html);
assert.equal(dialoguePairs(paired.project.beats[0].content).length,1);
assert.deepEqual(removeDualDialogue(JSON.parse(JSON.stringify(paired)),'beat',0),original,'Save/reopen and unpair preserve every field');
for(const protection of ['beat','block','layer','scene','omitted','unused','stale','missing']){
  const input=structuredClone(document),b=input.project.frontstageWhiteboard;
  if(protection==='beat')b.beats[0].locked=true;
  if(protection==='block')b.blocks[0].locked=true;
  if(protection==='layer')b.layers[0].locked=true;
  if(protection==='scene')input.project.beats[0].frontstageTextLocked=true;
  if(protection==='omitted')b.beats[0].omitted=true;
  if(protection==='unused')b.layers[0].unused=true;
  if(protection==='stale')input.project.beats[0].content='<p>Stale imported text</p>';
  const before=structuredClone(input);
  assert.throws(()=>pairDialogue(input,protection==='missing'?'unknown':'beat',0,2),undefined,protection);
  assert.deepEqual(input,before,protection+' rejection is atomic');
}
console.log(`PASS: ${fixtures.valid.length} shared lossless dual-dialogue fixtures, ${fixtures.invalid.length} invalid selections, malformed pairs and save/reopen`);
