import {remapAnnotationIDs} from './script-annotations.js';
import {duplicatedPairIDs} from './dual-dialogue.js';
import {blockLocked} from './board-operations.js';
const clone=value=>structuredClone(value);
export const sceneModel='oneBeatPerScene';
export const conversionCategories={notes:['notes'],breakdown:['breakdown','breakdownData'],attachments:['attachments'],production:['productionNotes','shootingNotes']};
export function duplicateBeat(document,id){
 const p=document.project,b=p.frontstageWhiteboard,original=b.beats.find(beat=>beat.id===id),scene=p.beats.find(s=>s.id===original?.sceneID);
 if(!original||!scene||original.locked||blockLocked(b,original.blockID)||scene.frontstageTextLocked)throw Error('Choose an unlocked beat to duplicate.');
 const copy=clone(original),next=clone(scene),sceneID=Math.max(p.nextId||1,...p.beats.map(s=>s.id+1));
 copy.html=duplicatedPairIDs(copy.html);copy.id=crypto.randomUUID();copy.sceneID=sceneID;copy.title+=' copy';next.id=sceneID;next.title=copy.title;next.summary=copy.synopsis||'';next.content=copy.html;
 for(const key of ['sceneNumber','versions','frontstageLegacySceneID'])delete next[key];
 const annotationMap=new Map();const newIDs=list=>Array.isArray(list)?list.map(item=>item&&typeof item==='object'&&item.id!=null?{...item,id:(()=>{const id=crypto.randomUUID();annotationMap.set(String(item.id),id);return id;})()}:item):list;
 if(next.notes)next.notes=newIDs(next.notes);for(const key of ['breakdown','breakdownData'])if(next[key]&&typeof next[key]==='object'&&!Array.isArray(next[key]))next[key]=Object.fromEntries(Object.entries(next[key]).map(([category,items])=>[category,newIDs(items)]));
 copy.html=remapAnnotationIDs(copy.html,annotationMap);next.content=copy.html;if(next.frontstageHeadingMarkup)next.frontstageHeadingMarkup=remapAnnotationIDs(next.frontstageHeadingMarkup,annotationMap);
 const ordered=[...b.beats].sort((a,b)=>a.order-b.order),index=ordered.findIndex(beat=>beat.id===id);copy.order=(original.order+(ordered[index+1]?.order??original.order+2))/2;copy.start=original.start+original.duration;
 const block=b.blocks.find(block=>block.id===copy.blockID);if(block?.standalone){const container=clone(block);container.id=crypto.randomUUID();container.position.x+=24;container.position.y+=64;b.blocks.push(container);copy.blockID=container.id;}else if(copy.position)copy.position={x:copy.position.x+24,y:copy.position.y+48};
 p.beats.push(next);p.nextId=sceneID+1;b.beats.push(copy);syncSceneMetadata(document);validateSceneModel(document);return copy.id;
}
export function isSceneModel(document){return document.project.frontstageSceneModel===sceneModel;}
export function validateSceneModel(document){
 const p=document.project;if(!isSceneModel(document))return;
 const all=[...(p.frontstageWhiteboard?.beats||[]),...(p.frontstagePullouts||[]).map(item=>item.beat)];
 if(!p.frontstageWhiteboard)return;
 for(const scene of p.beats){const owned=all.filter(b=>b.sceneID===scene.id);if(owned.length!==1)throw Error('This project requires one beat per scene. Update DOT or review a converted copy.');if(owned[0].title!==scene.title||(owned[0].synopsis||'')!==(scene.summary||''))throw Error('Scene title and summary must agree with their beat.');}
 if(all.some(b=>!p.beats.some(s=>s.id===b.sceneID)))throw Error('A beat references a missing scene.');
}
export function syncSceneMetadata(document){if(!isSceneModel(document))return;const p=document.project;for(const beat of [...p.frontstageWhiteboard.beats,...(p.frontstagePullouts||[]).map(entry=>entry.beat)]){const scene=p.beats.find(s=>s.id===beat.sceneID);if(scene){scene.title=beat.title;scene.summary=beat.synopsis||'';}}}
export function conversionGroups(document){const p=document.project,all=[...p.frontstageWhiteboard.beats,...(p.frontstagePullouts||[]).map(entry=>entry.beat)];return p.beats.map(scene=>({scene,beats:all.filter(b=>b.sceneID===scene.id).sort((a,b)=>a.order-b.order),conflict:all.some(b=>b.sceneID===scene.id&&(b.title!==scene.title||(b.synopsis||'')!==(scene.summary||'')))}));}
export function convertSceneCopy(document,choices={}){
 const next=clone(document),p=next.project,b=p.frontstageWhiteboard;delete p.frontstageSceneModel;
 p.frontstageLegacyScenes=clone(document.project);next.name=(document.name||'Screenplay')+' — converted';
 let nextID=Math.max(p.nextId||1,...p.beats.map(s=>s.id+1)),scenes=[];
 for(const {scene,beats:owned}of conversionGroups(next)){
  if(!owned.length){const blockID=crypto.randomUUID();b.blocks.push({id:blockID,name:'',standalone:true,layerID:b.layers[0].id,position:{x:60,y:60},width:224,collapsed:false,locked:false});const beat={id:crypto.randomUUID(),sceneID:scene.id,blockID,title:scene.title,synopsis:scene.summary||'',html:scene.content||'',characters:scene.characters||[],tags:[],kind:'story',color:'#a34eae',order:b.beats.length,start:b.beats.length*1.5,duration:1.5,omitted:!!scene.isDisabled,locked:false};b.beats.push(beat);owned.push(beat);}
  const mapped=[];
  owned.forEach((beat,index)=>{
   const s=clone(scene);s.id=index===0?scene.id:nextID++;s.title=beat.title;s.summary=beat.synopsis||'';s.content=beat.omitted?'':beat.html;s.isDisabled=!!beat.omitted;s.characters=beat.characters||[];
   if(index>0)delete s.sceneNumber;delete s.versions;s.frontstageLegacySceneID=scene.id;
   for(const [category,keys]of Object.entries(conversionCategories)){const targets=choices[scene.id]?.[category]||[owned[0].id];for(const key of keys){if(!targets.includes(beat.id))delete s[key];else if(index>0&&Array.isArray(s[key]))s[key]=s[key].map(value=>typeof value==='object'&&value?{...value,id:crypto.randomUUID(),frontstageSourceID:value.id}:value);}}
   beat.sceneID=s.id;mapped.push({beatID:beat.id,sceneID:s.id});scenes.push(s);
  });
  for(const day of p.frontstageProduction?.days||[]){if(!day.sceneIDs.includes(scene.id))continue;const targets=choices[scene.id]?.production||[owned[0].id];day.sceneIDs=day.sceneIDs.filter(id=>id!==scene.id).concat(mapped.filter(m=>targets.includes(m.beatID)).map(m=>m.sceneID));}
 }
 p.beats=scenes;p.nextId=nextID;p.frontstageSceneModel=sceneModel;
 const unused=new Set(b.layers.filter(l=>l.unused).map(l=>l.id));for(const s of scenes){const beat=b.beats.find(beat=>beat.sceneID===s.id);if(!beat||unused.has(b.blocks.find(block=>block.id===beat.blockID)?.layerID)){s.content='';s.isDisabled=true;}}
 syncSceneMetadata(next);validateSceneModel(next);return next;
}
export function updateBeatCard(document,id,patch){const p=document.project,b=p.frontstageWhiteboard,beat=b.beats.find(beat=>beat.id===id),scene=p.beats.find(scene=>scene.id===beat?.sceneID);if(!beat||beat.locked||blockLocked(b,beat.blockID)||scene?.frontstageTextLocked)throw Error('Unlock this scene before editing.');for(const key of ['title','synopsis'])if(typeof patch[key]==='string')beat[key]=patch[key];syncSceneMetadata(document);}
