import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {screenplayCommand,characterCue,DialogueContinuation,characterCompletions,headingCompletions,parentheticalCompletions} from '../Public/dialogue-rules.js';
const data=JSON.parse(await readFile(new URL('../../Tests/Fixtures/screenplay-writing-rules.json',import.meta.url),'utf8'));
for(const item of data.commands)assert.deepEqual(screenplayCommand(item.element,item.key,item.empty,item.selection),{element:item.target,placement:item.placement});
for(const item of data.cues){const cue=characterCue(item.source);assert.equal(cue.name,item.name);assert.deepEqual(cue.extensions,item.extensions);assert.equal(cue.hasContinuation,item.continued);assert.ok(!cue.withoutContinuation.includes('CONT'));}
for(const item of data.dialogues){const tracker=new DialogueContinuation(),generated=[];item.lines.forEach(([kind,text],index)=>{if(tracker.observe(kind,text))generated.push(index);});assert.deepEqual(generated,item.continued,item.name);}
assert.deepEqual(characterCompletions('MA (V.O.)',2,['KAMAL','MARY JANE']),{start:0,end:2,values:['MARY JANE']});
assert.deepEqual(characterCompletions('KAMAL (O)',8,[]),{start:6,end:9,values:['(O.S.)','(O.C.)']});
assert.deepEqual(headingCompletions('EXT. PARK - N',13,[]),{start:12,end:13,values:['NIGHT']});
assert.deepEqual(parentheticalCompletions('(over').values,['(over the phone)']);
console.log('PASS: shared screenplay commands, Unicode cue parsing, explicit extensions, component completions and continuation rules');
