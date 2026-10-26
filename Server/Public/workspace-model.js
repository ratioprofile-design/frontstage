import {isSceneModel} from './scene-model.js';
import {blockLocked} from './board-operations.js';
// Browser operations use the existing native project schema; callers commit atomically.
export const characterFields = ['occupation','backstory','psychology','physiology','sociology','wardrobeNotes','specialSkills','playingAge'];
export const castingStatuses = ['idea','in_talks','audition_requested','self_tape_received','callback','chemistry_read','offer_sent','contract_signed','on_board','passed','hold'];
export const categories = ['CAST','EXTRAS','STUNTS','VEHICLES','PROPS','SFX','WARDROBE','MAKEUP','ANIMALS','SOUND','SET_DRESSING','GREENERY','SPECIAL_EQUIPMENT','LIGHTING_GRIP','SAFETY'];
export const productionFields = {locationName:'Location',locationAddress:'Location Address',parkingInstructions:'Parking Instructions',hospitalName:'Hospital',hospitalAddress:'Hospital Address',hospitalEmergencyPhone:'Hospital / Emergency Phone',director:'Director',producer:'Producer',firstAd:'First AD',cinematographer:'Cinematographer',weather:'Weather',notes:'Notes'};
export const studioFields = {research:['Source URL','Category'],crew:['Role','Email','Phone','Availability','Department'],continuity:['Status','Costume','Props','Makeup','Take'],shot:['Shot Number','Size','Angle','Lens','Movement','Equipment','Status'],audition:['Character','Actor','Audition Date','Rating','Status','Link']};
export const label = key => key.replace(/([a-z])([A-Z])/g,'$1 $2').replaceAll('_',' ').replace(/\b\w/g, c => c.toUpperCase());
const uuid = () => crypto.randomUUID();
const own = (o,k,v) => Object.defineProperty(o,k,{value:v,writable:true,enumerable:true,configurable:true});
const object = (o, key) => { if (o[key] != null && (typeof o[key] !== 'object' || Array.isArray(o[key]))) throw Error(`Unsupported ${key} data; the original is preserved.`); return o[key] ||= {}; };
export function scene(document,id) { const s=document.project.beats.find(s=>s.id===id); if(!s) throw Error('Select a scene.'); return s; }
export function board(document) { return document.project.frontstageWhiteboard; }
export function activeBeats(document) { const b=board(document), unused=new Set(b.layers.filter(l=>l.unused).map(l=>l.id)), inactive=new Set(b.blocks.filter(x=>unused.has(x.layerID)).map(x=>x.id)); return b.beats.filter(x=>!x.omitted&&!inactive.has(x.blockID)).sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id)); }
export function scriptSegments(document,{includeInactive=false}={}) {
  const scenes=document.project.beats, byID=new Map(scenes.map(s=>[s.id,s])), seen=new Set(), result=[];
  for(const beat of (includeInactive?[...board(document).beats].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id)):activeBeats(document))) {
    const s=byID.get(beat.sceneID); if(!s||(!includeInactive&&s.isDisabled)) continue;
    const last=result.at(-1); if(last?.scene.id===s.id) { last.html+=beat.html; last.beatIDs.push(beat.id); }
    else { result.push({scene:s,html:beat.html,beatIDs:[beat.id],number:result.find(r=>r.scene.id===s.id)?.number||s.sceneNumber||String(seen.size+1),continuation:seen.has(s.id)}); seen.add(s.id); }
  }
  for(const s of scenes) if((includeInactive||!s.isDisabled)&&!seen.has(s.id)&&(includeInactive||s.content)) result.push({scene:s,html:s.content,beatIDs:[],number:s.sceneNumber||String(new Set(result.map(r=>r.scene.id)).size+1),continuation:false});
  return result;
}
export function heading(s) { const h=s.slug||{}; return `${h.prefix||'INT.'} ${(h.location||'UNTITLED SCENE').trim()} - ${h.time||'DAY'}`.toUpperCase(); }
export function createCharacter(document,name) {
  const key=name.trim().toUpperCase(); if(!key) throw Error('A character needs a name.');
  const roles=object(document.project,'characterData');
  if(Object.entries(roles).some(([id,r])=>id.toUpperCase()===key||r.name?.toUpperCase()===key)) throw Error('A character with that name already exists.');
  own(roles,key,{id:uuid(),name:key,backstory:'',artists:[],relationships:[],images:[]}); return key;
}
export function assignCharacter(document,id,key,assigned) {
  const s=scene(document,id), b=board(document), members=b.beats.filter(x=>x.sceneID===id);
  if(!Object.hasOwn(document.project.characterData||{},key)) throw Error('Character not found.');
  s.characters=assigned?[...new Set([...(s.characters||[]),key])]:(s.characters||[]).filter(x=>x!==key);
  if(assigned&&!members.some(x=>x.characters.includes(key))) { const first=activeBeats(document).find(x=>x.sceneID===id); if(first) first.characters.push(key); }
  if(!assigned) members.forEach(x=>x.characters=x.characters.filter(x=>x!==key));
}
export function addActor(document,key,name) { if(!name.trim()) throw Error('An actor needs a name.'); const r=document.project.characterData[key], a={id:uuid(),name:name.trim(),rank:(r.artists||[]).length+1,status:'idea',notes:''}; (r.artists||=[]).push(a); return a.id; }
export function confirmActor(document,key,id) { const r=document.project.characterData[key]; if(id&&!r.artists.some(a=>a.id===id&&a.status!=='passed')) throw Error('Choose an available casting option.'); if(id) r.confirmedArtistId=id; else delete r.confirmedArtistId; }
export function breakdownEntries(s) { const storage=s.breakdownData&&typeof s.breakdownData==='object'?'breakdownData':'breakdown', root=s[storage]||{}; return Object.keys(root).sort().flatMap(bucket=>Array.isArray(root[bucket])?root[bucket].map((item,index)=>({storage,bucket,index,...(typeof item==='string'?{name:item}:item)})):[]); }
export function addRequirement(document,id,category,name,count=1,description='') { if(!categories.includes(category)||!name.trim()||!Number.isInteger(count)||count<1||count>100000) throw Error('Choose a category, name and positive quantity.'); const s=scene(document,id), key=s.breakdownData&&typeof s.breakdownData==='object'?'breakdownData':'breakdown'; (object(s,key)[category]||=[]).push({id:uuid(),name:name.trim(),category,count,description}); }
export function captureRevision(document,id,name) { if(!name.trim()) throw Error('A revision needs a name.'); const s=scene(document,id), revision={id:uuid(),frontstageLabel:name.trim(),timestamp:Date.now(),title:s.title,content:s.content,summary:s.summary||'',frontstageEditorial:{slug:s.slug??null,sceneNumber:s.sceneNumber??null},frontstageSnippets:structuredClone(board(document).beats.filter(b=>b.sceneID===id))}; (s.versions||=[]).push(revision); return revision.id; }
export function restoreRevision(document,id,revisionID) {
  const s=scene(document,id), revision=s.versions?.find(v=>v.id===revisionID), b=board(document), current=b.beats.filter(x=>x.sceneID===id);
  if(!revision||typeof revision.content!=='string') throw Error('Revision not found.');
  if(s.frontstageTextLocked||current.some(beat=>beat.locked||blockLocked(b,beat.blockID))) throw Error('Unlock the scene and its beats before restoring a revision.');
  if(revision.frontstageSnippets&&revision.frontstageSnippets.some(beat=>beat.sceneID!==id||!b.blocks.some(block=>block.id===beat.blockID)))throw Error('A saved beat container is missing or belongs to another scene. Restore the container before restoring this snapshot.');
  if(!revision.frontstageSnippets&&current.length>1) throw Error('This older revision has no snippet boundaries.');
  if(revision.frontstageSnippets?.some(beat=>(document.project.frontstagePullouts||[]).some(entry=>entry.id===beat.id)))throw Error('Restore pulled-out beats from Research before restoring this snapshot.');
  captureRevision(document,id,`Before restoring ${revision.frontstageLabel||'revision'}`);
  s.title=revision.title??s.title;s.summary=revision.summary??s.summary;
  if(revision.frontstageEditorial) for(const key of ['slug','sceneNumber']) { if(revision.frontstageEditorial[key]==null) delete s[key]; else s[key]=structuredClone(revision.frontstageEditorial[key]); }
  if(revision.frontstageSnippets) {
    if(!revision.frontstageSnippets.length)s.content=revision.content;
    const oldIDs=new Set(current.map(x=>x.id)); b.beats=b.beats.filter(x=>x.sceneID!==id).concat(structuredClone(revision.frontstageSnippets));
    const ids=new Set(b.beats.map(x=>x.id)); b.dependencies=b.dependencies.filter(e=>!(oldIDs.has(e.cause)||oldIDs.has(e.effect))||(ids.has(e.cause)&&ids.has(e.effect)));
  } else if(current[0]) { current[0].html=revision.content; current[0].title=revision.title??current[0].title; }
  else s.content=revision.content;
}
export function production(document) { const p=object(document.project,'frontstageProduction'); if(p.schemaVersion!=null&&p.schemaVersion!==1) throw Error('Unsupported production version.'); p.schemaVersion=1; p.days||=[]; return p; }
export function addDay(document,date) { if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date).toISOString().slice(0,10)!==date) throw Error('Choose a valid shooting date.'); const p=production(document), day={id:uuid(),number:Math.max(0,...p.days.map(d=>d.number))+1,date,callTime:'06:00',wrapTime:'18:00',sceneIDs:[],castCalls:{}};p.days.push(day);return day.id; }
export function assignDay(document,id,dayID) { scene(document,id); const p=production(document); if(dayID&&!p.days.some(d=>d.id===dayID)) throw Error('Shooting day not found.'); for(const d of p.days) { d.sceneIDs=d.sceneIDs.filter(x=>x!==id); if(d.id===dayID)d.sceneIDs.push(id); } }
export function scheduleWarnings(document,day) {
  const minutes=t=>{if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(t))return NaN;const[h,m]=t.split(':').map(Number);return h*60+m;};
  const start=minutes(day.callTime),wrap=minutes(day.wrapTime),date=Date.parse(day.date+'T00:00:00Z');
  if(!Number.isFinite(start+wrap+date))return ['Invalid shooting-day date or time.'];
  const duration=wrap>start?wrap-start:wrap+1440-start,scenes=scheduledScenes(document,day),load=scenes.reduce((sum,s)=>sum+(document.project.frontstageProduction?.sceneEstimates?.[s.id]??60),0),warnings=[];
  if(load>duration)warnings.push(`Estimated scenes exceed the call-to-wrap window by ${load-duration} minutes.`);
  if(duration>720)warnings.push('The planned shooting window exceeds 12 hours.');
  if(scenes.length!==day.sceneIDs.length)warnings.push('Omitted or missing scenes remain assigned; they are excluded from exports.');
  const ordered=orderedDays(document),i=ordered.findIndex(d=>d.id===day.id),previous=ordered[i-1];
  if(previous){const call=minutes(previous.callTime),end=minutes(previous.wrapTime),gap=(date-Date.parse(previous.date+'T00:00:00Z'))/60000+start-(end>call?end:end+1440);if(gap<0)warnings.push('This day overlaps the previous shooting day.');else if(gap<720)warnings.push('Less than 12 hours of turnaround after the previous day.');}
  return warnings;
}
export function orderedDays(document){return [...(document.project.frontstageProduction?.days||[])].sort((a,b)=>a.date.localeCompare(b.date)||a.number-b.number);}
export function scheduledScenes(document,day){return day.sceneIDs.map(id=>document.project.beats.find(s=>s.id===id)).filter(s=>s&&!s.isDisabled);}
export function scheduleRows(document){const scenes=document.project.beats.filter(s=>!s.isDisabled);return [['Day','Date','Crew Call','Wrap','Scene ID','Scene Number','Heading','Estimated Minutes','Characters'],...orderedDays(document).flatMap(day=>scheduledScenes(document,day).map(s=>[day.number,day.date,day.callTime,day.wrapTime,s.id,s.sceneNumber||String(scenes.indexOf(s)+1),heading(s),document.project.frontstageProduction?.sceneEstimates?.[s.id]??60,(s.characters||[]).join('; ')]))];}
export function dayOutRows(document){const days=orderedDays(document),roles=[...new Set(days.flatMap(day=>scheduledScenes(document,day).flatMap(s=>s.characters||[])))].sort();return [['Character',...days.map(d=>`Day ${d.number} ${d.date}`)],...roles.map(role=>{const work=days.map(day=>scheduledScenes(document,day).some(s=>s.characters?.includes(role))),first=work.indexOf(true),last=work.lastIndexOf(true);return[role,...work.map((w,i)=>w?(i===first&&i===last?'SWF':i===first?'SW':i===last?'WF':'W'):i>first&&i<last?'H':'')];})];}
export function studio(document) { const s=object(document.project,'frontstageStudio'); if(s.version!=null&&s.version!==1) throw Error('Unsupported research/media version.');s.version=1;s.records||=[];s.assets||=[];return s; }
export function addRecord(document,kind,id) { if(!studioFields[kind])throw Error('Unknown record type.');const r={id:uuid(),kind,title:`Untitled ${kind}`,body:'',fields:{},assetIDs:[]};if(id!=null)r.sceneID=id;studio(document).records.push(r);return r.id; }
export function addAttachment(document,recordID,filename,data) { const s=studio(document), r=s.records.find(r=>r.id===recordID);if(!r)throw Error('Record no longer exists.');const size=x=>Math.floor(x.length*3/4)-(x.endsWith('==')?2:x.endsWith('=')?1:0);if(size(data)>10*1024*1024||s.assets.reduce((n,a)=>n+size(a.data),0)+size(data)>64*1024*1024)throw Error('Attachments allow 10 MB per file and 64 MB per project.');const asset={id:uuid(),filename:filename.split(/[\\/]/).at(-1),data};s.assets.push(asset);r.assetIDs.push(asset.id);return asset.id; }
export function setTypography(document,value) { if(!value.fontName.trim()||value.fontName.length>120||!Number.isFinite(value.fontSize)||value.fontSize<8||value.fontSize>24||!Number.isFinite(value.lineHeight)||value.lineHeight<value.fontSize||value.lineHeight>40||!Number.isFinite(value.paragraphSpacing)||value.paragraphSpacing<0||value.paragraphSpacing>36)throw Error('Choose a valid font size, line height and paragraph spacing.'); document.project.frontstageScriptLayout=value; }
export function splitBeat(document,id,firstHTML,secondHTML) { const b=board(document), beat=b.beats.find(x=>x.id===id);if(!beat||beatLocked(b,beat)||scene(document,beat.sceneID).frontstageTextLocked)throw Error('Select an unlocked beat.');const ordered=[...b.beats].sort((a,b)=>a.order-b.order),index=ordered.findIndex(x=>x.id===id),next={...structuredClone(beat),id:uuid(),title:beat.title+' (continued)',html:secondHTML,order:(beat.order+(ordered[index+1]?.order??beat.order+2))/2,start:beat.start+beat.duration/2,duration:beat.duration/2};beat.html=firstHTML;beat.duration=next.duration;for(const e of b.dependencies)if(e.cause===id)e.cause=next.id;if(isSceneModel(document)){const sceneID=Math.max(document.project.nextId||1,...document.project.beats.map(s=>s.id+1));const original=scene(document,beat.sceneID);document.project.beats.push({id:sceneID,title:next.title,summary:next.synopsis||'',content:next.html,slug:structuredClone(original.slug)});document.project.nextId=sceneID+1;next.sceneID=sceneID;}b.beats.push(next);b.dependencies.push({id:uuid(),cause:id,effect:next.id,reason:'',reference:false});return next.id; }
export function csv(rows) { return rows.map(row=>row.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(',')).join('\r\n'); }

function beatLocked(board,beat) { if(beat.locked)return true;let block=board.blocks.find(b=>b.id===beat.blockID);const seen=new Set();while(block&&!seen.has(block.id)){if(block.locked||board.layers.find(l=>l.id===block.layerID)?.locked)return true;seen.add(block.id);block=board.blocks.find(b=>b.id===block.parentID);}return false; }

export function breakdownRows(document){return [['Scene ID','Scene','Category','Item','Quantity','Notes'],...document.project.beats.filter(s=>!s.isDisabled).flatMap(s=>breakdownEntries(s).map(item=>[s.id,heading(s),item.category||item.bucket,item.name,item.count||1,item.description||'']))];}
export function removeStudioAsset(document,recordID,assetID){const s=studio(document),record=s.records.find(r=>r.id===recordID);if(!record)throw Error('Record no longer exists.');record.assetIDs=record.assetIDs.filter(id=>id!==assetID);pruneAssets(s);}
export function removeStudioRecord(document,id){const s=studio(document);s.records=s.records.filter(r=>r.id!==id);pruneAssets(s);}
function pruneAssets(s){const used=new Set(s.records.flatMap(r=>r.assetIDs));s.assets=s.assets.filter(a=>used.has(a.id));}
