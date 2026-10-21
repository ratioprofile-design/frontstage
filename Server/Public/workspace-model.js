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
export function scriptSegments(document) {
  const scenes=document.project.beats, byID=new Map(scenes.map(s=>[s.id,s])), seen=new Set(), result=[];
  for(const beat of activeBeats(document)) {
    const s=byID.get(beat.sceneID); if(!s||s.isDisabled) continue;
    const last=result.at(-1); if(last?.scene.id===s.id) { last.html+=beat.html; last.beatIDs.push(beat.id); }
    else { result.push({scene:s,html:beat.html,beatIDs:[beat.id],number:s.sceneNumber||String(scenes.filter(s=>!s.isDisabled).findIndex(x=>x.id===s.id)+1),continuation:seen.has(s.id)}); seen.add(s.id); }
  }
  for(const s of scenes) if(!s.isDisabled&&!seen.has(s.id)&&s.content) result.push({scene:s,html:s.content,beatIDs:[],number:s.sceneNumber||String(scenes.indexOf(s)+1),continuation:false});
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
  if(s.frontstageTextLocked) throw Error('Unlock the scene script before restoring a revision.');
  if(!revision.frontstageSnippets&&current.length>1) throw Error('This older revision has no snippet boundaries.');
  captureRevision(document,id,`Before restoring ${revision.frontstageLabel||'revision'}`);
  s.title=revision.title??s.title;s.summary=revision.summary??s.summary;
  if(revision.frontstageEditorial) for(const key of ['slug','sceneNumber']) { if(revision.frontstageEditorial[key]==null) delete s[key]; else s[key]=structuredClone(revision.frontstageEditorial[key]); }
  if(revision.frontstageSnippets) {
    const oldIDs=new Set(current.map(x=>x.id)); b.beats=b.beats.filter(x=>x.sceneID!==id).concat(structuredClone(revision.frontstageSnippets));
    const ids=new Set(b.beats.map(x=>x.id)); b.dependencies=b.dependencies.filter(e=>!(oldIDs.has(e.cause)||oldIDs.has(e.effect))||(ids.has(e.cause)&&ids.has(e.effect)));
  } else if(current[0]) { current[0].html=revision.content; current[0].title=revision.title??current[0].title; }
  else s.content=revision.content;
}
export function production(document) { const p=object(document.project,'frontstageProduction'); if(p.schemaVersion!=null&&p.schemaVersion!==1) throw Error('Unsupported production version.'); p.schemaVersion=1; p.days||=[]; return p; }
export function addDay(document,date) { if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||new Date(date).toISOString().slice(0,10)!==date) throw Error('Choose a valid shooting date.'); const p=production(document), day={id:uuid(),number:Math.max(0,...p.days.map(d=>d.number))+1,date,callTime:'06:00',wrapTime:'18:00',sceneIDs:[],castCalls:{}};p.days.push(day);return day.id; }
export function assignDay(document,id,dayID) { scene(document,id); const p=production(document); if(dayID&&!p.days.some(d=>d.id===dayID)) throw Error('Shooting day not found.'); for(const d of p.days) { d.sceneIDs=d.sceneIDs.filter(x=>x!==id); if(d.id===dayID)d.sceneIDs.push(id); } }
export function scheduleWarnings(document,day) { const minutes=t=>{const [h,m]=t.split(':').map(Number);return h*60+m;};let duration=minutes(day.wrapTime)-minutes(day.callTime);if(duration<=0)duration+=1440;const load=day.sceneIDs.reduce((sum,id)=>sum+(document.project.frontstageProduction?.sceneEstimates?.[id]??60),0);return load>duration?[`Scene estimates exceed the shooting window by ${load-duration} minutes.`]:[]; }
export function studio(document) { const s=object(document.project,'frontstageStudio'); if(s.version!=null&&s.version!==1) throw Error('Unsupported research/media version.');s.version=1;s.records||=[];s.assets||=[];return s; }
export function addRecord(document,kind,id) { if(!studioFields[kind])throw Error('Unknown record type.');const r={id:uuid(),kind,title:`Untitled ${kind}`,body:'',fields:{},assetIDs:[]};if(id!=null)r.sceneID=id;studio(document).records.push(r);return r.id; }
export function addAttachment(document,recordID,filename,data) { const s=studio(document), r=s.records.find(r=>r.id===recordID);if(!r)throw Error('Record no longer exists.');const size=x=>Math.floor(x.length*3/4)-(x.endsWith('==')?2:x.endsWith('=')?1:0);if(size(data)>10*1024*1024||s.assets.reduce((n,a)=>n+size(a.data),0)+size(data)>64*1024*1024)throw Error('Attachments allow 10 MB per file and 64 MB per project.');const asset={id:uuid(),filename:filename.split(/[\\/]/).at(-1),data};s.assets.push(asset);r.assetIDs.push(asset.id);return asset.id; }
export function setTypography(document,value) { if(!value.fontName.trim()||value.fontName.length>120||!Number.isFinite(value.fontSize)||value.fontSize<8||value.fontSize>24||!Number.isFinite(value.lineHeight)||value.lineHeight<value.fontSize||value.lineHeight>40||!Number.isFinite(value.paragraphSpacing)||value.paragraphSpacing<0||value.paragraphSpacing>36)throw Error('Choose a valid font size, line height and paragraph spacing.'); document.project.frontstageScriptLayout=value; }
export function splitBeat(document,id,firstHTML,secondHTML) { const b=board(document), beat=b.beats.find(x=>x.id===id);if(!beat||beatLocked(b,beat)||scene(document,beat.sceneID).frontstageTextLocked)throw Error('Select an unlocked beat.');const ordered=[...b.beats].sort((a,b)=>a.order-b.order),index=ordered.findIndex(x=>x.id===id),next={...structuredClone(beat),id:uuid(),title:beat.title+' (continued)',html:secondHTML,order:(beat.order+(ordered[index+1]?.order??beat.order+2))/2,start:beat.start+beat.duration/2,duration:beat.duration/2};beat.html=firstHTML;beat.duration=next.duration;for(const e of b.dependencies)if(e.cause===id)e.cause=next.id;b.beats.push(next);b.dependencies.push({id:uuid(),cause:id,effect:next.id,reason:'',reference:false});return next.id; }
export function csv(rows) { return rows.map(row=>row.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(',')).join('\r\n'); }

function beatLocked(board,beat) { if(beat.locked)return true;let block=board.blocks.find(b=>b.id===beat.blockID);const seen=new Set();while(block&&!seen.has(block.id)){if(block.locked||board.layers.find(l=>l.id===block.layerID)?.locked)return true;seen.add(block.id);block=board.blocks.find(b=>b.id===block.parentID);}return false; }
