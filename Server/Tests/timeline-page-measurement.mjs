import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {timelinePageWeights} from '../Public/timeline-page-measurement.js';
import {timelineModel} from '../Public/story-timeline.js';
const fixture=JSON.parse(await readFile(new URL('../../Tests/Fixtures/timeline-page-measurement.json',import.meta.url),'utf8'));
for(const entry of fixture.cases){const result=timelinePageWeights(entry.ids,entry.spans);if(entry.expected)for(const[id,value]of Object.entries(entry.expected))assert.ok(Math.abs(result[id]-value)<.0001,entry.name);else assert.equal(result,null,entry.name);}
const doc=JSON.parse(await readFile(new URL('../../Tests/Fixtures/write-panels.frontstage',import.meta.url),'utf8')),before=structuredClone(doc),counts={'beat-1':.5,'beat-2':1.25},model=timelineModel(doc.project.frontstageWhiteboard,doc.project.beats,[],'pages',1,{},counts);
assert.equal(model.typesetPages,true);assert.equal(model.beatPages['beat-2'],.5);assert.deepEqual(model.beatPageCounts,counts);assert.deepEqual(doc,before);
const incomplete=timelineModel(doc.project.frontstageWhiteboard,doc.project.beats,[],'pages',1,{}, {'beat-1':10});assert.equal(incomplete.typesetPages,false);assert.notEqual(incomplete.beatPages['beat-2'],10);
doc.project.frontstageWhiteboard.beats[0].timelineDuration=3;const time=timelineModel(doc.project.frontstageWhiteboard,doc.project.beats,[],'time',1,{},counts);assert.equal(time.beatTimes['beat-2'],3);assert.equal(time.beatPages['beat-2'],.5);
console.log('PASS: shared measured page spans, complete-map fallback, explicit duration overrides and read-only projection');
