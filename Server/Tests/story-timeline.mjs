import assert from 'node:assert/strict';
import {timelineModel,timelineClock,timelinePreferences} from '../Public/story-timeline.js';
const board={layers:[{id:'main'}],blocks:[{id:'a',layerID:'main'}],beats:[{id:'one',sceneID:1,blockID:'a',order:0,start:20,duration:1,title:'One',color:'#ffffff',tags:['Danger'],characters:['VENBA'],html:'',timelineDuration:4,emotionChanges:{Danger:20},tensions:{Danger:3}},{id:'two',sceneID:1,blockID:'a',order:1,start:100,duration:1,title:'Two',color:'#ffffff',tags:['Danger'],characters:[],html:'',emotionChanges:{Danger:80},emotionAbsoluteTags:['Danger']}]};
const model=timelineModel(board,[{id:1,title:'Classroom',slug:{time:'DAY'}}]);
assert.deepEqual(model.tracks.find(t=>t.kind==='beats').items.map(i=>i.start),[0,1]);
assert.deepEqual(model.tracks.find(t=>t.kind==='tags').items.map(i=>i.value),[20,80]);
assert.equal(model.tracks.find(t=>t.kind==='heat').items.length,1);
assert.equal(timelineModel(board,[] ,[],'time').beats[1].start,4);
assert.equal(timelineClock(12.5),'00:12:30');
console.log('PASS: serialized beat/time/page projections, emotion checkpoints and tension heat map');

const carried=structuredClone(board);carried.beats.push({...carried.beats[1],id:'three',order:2,emotionChanges:undefined,emotionAbsoluteTags:undefined});assert.deepEqual(timelineModel(carried,[]).tracks.find(t=>t.kind==='tags').items.map(i=>i.value),[20,80,80]);

const structural=timelineModel(board,[],[{id:'ep1',title:'Episode One',unit:0,type:'episode'},{id:'act',title:'Act One',unit:0,type:'act'},{id:'ep2',title:'Episode Two',unit:50,type:'episode'}]);
assert.equal(structural.tracks.find(t=>t.kind==='episodes').items[0].duration,1);
assert.ok(structural.tracks.find(t=>t.kind==='acts').items[0].duration>1);
const rate=timelineModel(board,[],[],'time',2);assert.equal(rate.beats[0].duration,4);assert.equal(rate.beats[1].duration,2/55);
const mini=timelinePreferences(false),full=timelinePreferences(true);full.lines=3;
assert.equal(mini.lines,2);assert.ok(mini.hidden.has('characters'));assert.ok(!full.hidden.has('characters'));
assert.equal(timelinePreferences(true,{...full,collapsed:[],hidden:[]}).lines,3);
assert.equal(timelinePreferences(true,{...full,scale:Infinity}).scale,60);
console.log('PASS: independent structural levels, minutes/page overrides and separate mini/full preferences');

const organized=timelineModel(board,[],[],'beats',1,{tags:{Danger:'Dangers'},characters:{VENBA:'Family'}});
assert.equal(organized.tracks.find(t=>t.id==='tags:Danger').group,'Dangers');
assert.equal(organized.tracks.find(t=>t.id==='characters:VENBA').group,'Family');
assert.equal(timelineModel(board,[]).tracks.find(t=>t.id==='tags:Danger').group,'General');
assert.equal(timelineModel(board,[],[],'beats',1,{tags:{Danger:22}}).tracks.find(t=>t.id==='tags:Danger').group,'General');
assert.equal(timelinePreferences(true,{...full,colorStrength:.35,collapsed:['group:tags:Dangers'],hidden:[]}).colorStrength,.35);
assert.ok(timelinePreferences(true,{...full,collapsed:['group:tags:Dangers'],hidden:[]}).collapsed.has('group:tags:Dangers'));
console.log('PASS: tag categories, character groups and persistent display preferences');

const headings=[
 {id:1,slug:{prefix:'INT.',location:' Café மருத்துவமனை ',time:'DAY'}},
 {id:2,slug:{prefix:' int. ',location:'cafe\u0301 மருத்துவமனை',time:' day '}},
 {id:3,slug:{prefix:'EXT.',location:'Café மருத்துவமனை',time:'DAY'}},
 {id:4,slug:{prefix:'INT.',location:'Café மருத்துவமனை',time:'NIGHT'}},
 {id:5,slug:{prefix:'INT.',location:'Café மருத்துவமனை',time:'DAY'}},
 {id:6,slug:{prefix:'INT.',location:'',time:'DAY'}},
 {id:7,slug:{prefix:'INT.',location:'',time:'DAY'}}
];
const grouped=structuredClone(board);grouped.beats=headings.map((s,i)=>({...structuredClone(board.beats[0]),id:'span-'+i,sceneID:s.id,order:i,start:i*3,timelineDuration:i+1}));
const before=structuredClone(grouped);
for(const base of ['beats','time','pages']){
 const m=timelineModel(grouped,headings,[],base),spans=m.tracks.find(t=>t.kind==='scenes').items;
 assert.equal(spans.length,6);assert.deepEqual(spans[0].memberBeatIDs,['span-0','span-1']);
 assert.equal(spans[0].duration,m.beats[0].duration+m.beats[1].duration);
 assert.deepEqual(spans.slice(1).flatMap(s=>s.memberBeatIDs),['span-2','span-3','span-4','span-5','span-6']);
}
assert.deepEqual(grouped,before);
assert.equal(timelinePreferences(true,{...full,lines:5,titleDisplay:'full',collapsed:[],hidden:[]}).titleDisplay,'full');
assert.equal(timelinePreferences(true,{...full,lines:5,titleDisplay:'unknown',collapsed:[],hidden:[]}).titleDisplay,'reference');
assert.equal(timelinePreferences(false,{...full,lines:1,collapsed:[],hidden:[]}).lines,1);
console.log('PASS: normalized full-heading scene spans, explicit membership, time bases and title preference migration');
