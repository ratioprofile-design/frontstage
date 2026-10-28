// Keep the pure rules in parity with FrontstageCore/ScreenplayWritingRules.swift.
export const screenplayElements=['action','character','dialogue','parenthetical','transition','shot','lyrics','slugline'];
export const wrappedParenthetical=source=>!source.trim()?'()':(source.startsWith('(')?'':'(')+source+(source.endsWith(')')?'':')');
export const emptyParenthetical=source=>!source.replace(/[()]/g,'').trim();
export const voiceExtensions=['(V.O.)','(O.S.)','(O.C.)',"(CONT'D)"];
export const deliveryNotes=['(beat)','(quietly)','(over the phone)','(whispering)','(to himself)','(to herself)','(into phone)'];
export const headingTimes=['DAY','NIGHT','MORNING','AFTERNOON','EVENING','DAWN','DUSK','LATER','CONTINUOUS','SAME TIME'];
export const normalized=text=>text.normalize('NFC').trim().toUpperCase().replace(/\s+/g,' ');
export function characterCue(source){
 let remaining=source.trim(),extensions=[],match;
 const suffix=/\s*\((?:V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT['’]?D|CONT\.?|CONTINUED|OVER THE PHONE|ON THE PHONE|INTO PHONE|OVER PHONE|PRE-LAP|FILTERED)\)\s*$/i;
 while((match=suffix.exec(remaining))){extensions.unshift(match[0].trim());remaining=remaining.slice(0,match.index);}
 const name=normalized(remaining),hasContinuation=extensions.some(e=>normalized(e).startsWith('(CONT'));
 return {name,extensions,hasContinuation,withoutContinuation:[name,...extensions.filter(e=>!normalized(e).startsWith('(CONT'))].join(' ')};
}
export const elementShortcuts=['slugline','action','character','dialogue','parenthetical','transition','shot','lyrics'];
export function screenplayCommand(element,key,empty,selection=false){
 if(key==='ForceAction')return {element:'action',placement:empty?'inPlace':'afterParagraph'};
 if(key==='Backtab')return {element:screenplayElements[(screenplayElements.indexOf(element)+screenplayElements.length-1)%screenplayElements.length],placement:'inPlace'};
 if(element==='slugline')return {element:'action',placement:'body'};
 if(key==='Tab'){
  if(element==='character')return {element:'transition',placement:'inPlace'};
  if(element==='transition')return {element:'action',placement:'inPlace'};
  return {element:element==='dialogue'?'parenthetical':element==='parenthetical'?'dialogue':'character',placement:empty||selection?'inPlace':'afterParagraph'};
 }
 if(element==='transition')return {element:'slugline',placement:'newScene'};
 const next=element==='character'||element==='parenthetical'?'dialogue':element==='dialogue'?'character':element==='lyrics'?'lyrics':'action';
 return {element:next,placement:empty&&!['action','lyrics'].includes(element)?'inPlace':['character','parenthetical','transition','shot'].includes(element)?'afterParagraph':'split'};
}
export class DialogueContinuation{
 constructor(lastSpeaker=null){this.lastSpeaker=lastSpeaker==null?null:characterCue(lastSpeaker).name;this.cue=null;}
 observe(element,text){
  if(element==='slugline'){this.lastSpeaker=null;this.cue=null;return false;}
  if(element==='character'){this.cue=characterCue(text);return !!this.cue.name&&this.cue.name===this.lastSpeaker&&!this.cue.hasContinuation;}
  if(element==='dialogue'&&text.trim()&&this.cue?.name)this.lastSpeaker=this.cue.name;
  if(!['dialogue','parenthetical'].includes(element))this.cue=null;
  return false;
 }
}
function matches(choices,typed){const prefix=normalized(typed),seen=new Set();return choices.filter(value=>{const key=normalized(value);if(!key||!key.startsWith(prefix)||key===prefix||seen.has(key))return false;seen.add(key);return true;}).slice(0,12);}
export function headingCompletions(source,caret,headings=[]){
 const offset=Math.max(0,Math.min(caret,source.length)),prefix=/^(INT\.\/EXT\.|EXT\.\/INT\.|INT\.|EXT\.|I\/E\.)(\s+)/i.exec(source),separator=[...source.matchAll(/\s+[-–—]\s*/g)].at(-1);
 let start=0,end=prefix?prefix[1].length:source.search(/\s/),choices=['INT.','EXT.','INT./EXT.','EXT./INT.','I/E.'];
 if(separator&&offset>=separator.index+separator[0].length){start=separator.index+separator[0].length;end=source.length;choices=headingTimes;}
 else if(prefix&&offset>=prefix[0].length){start=prefix[0].length;end=separator?.index??source.length;choices=headings.map(h=>{if(typeof h==='object')return normalized(h.location||'');const rest=h.replace(/^(?:INT\.\/EXT\.|EXT\.\/INT\.|INT\.|EXT\.|I\/E\.)\s*/i,''),split=[...rest.matchAll(/\s+[-–—]\s*/g)].at(-1);return normalized(split?rest.slice(0,split.index):rest);});}
 if(end<0)end=source.length;return {start,end:Math.max(start,end),values:matches(choices,source.slice(start,offset))};
}
export function characterCompletions(source,caret,names=[]){
 const offset=Math.max(0,Math.min(caret,source.length)),before=source.slice(0,offset),open=before.lastIndexOf('(');
 if(open>=0&&before.slice(0,open).trim()){const close=source.indexOf(')',offset);return {start:open,end:close<0?source.length:close+1,values:matches(voiceExtensions,source.slice(open,offset))};}
 const start=source.indexOf('('),end=(start<0?source:source.slice(0,start)).trimEnd().length;
 return {start:0,end,values:matches(names.map(n=>characterCue(n).name),before)};
}
export function parentheticalCompletions(source,caret=source.length){return {start:0,end:source.length,values:matches(deliveryNotes,source.slice(0,caret))};}
export function paragraphKind(node){return screenplayElements.find(k=>node.classList?.contains('sc-'+k))||'action';}
export function scriptParagraphs(root){
 const selector=screenplayElements.map(k=>'.sc-'+k).join(',');
 return [...root.querySelectorAll(selector)].filter(n=>!n.querySelector(selector));
}
// Generated CSS tokens never enter textContent, saved HTML, names, or undo history.
export function decorateDialogue(root,seed=null,flags=null){
 const tracker=new DialogueContinuation(seed),ordinals=new Map();
 for(const node of scriptParagraphs(root)){const kind=paragraphKind(node);let generated=tracker.observe(kind,node.textContent);if(kind==='character'&&node.dataset.beatId){const id=node.dataset.beatId,index=ordinals.get(id)||0;ordinals.set(id,index+1);generated=flags?.[id]?.[index]??generated;}if(generated)node.dataset.autoContinuation='true';else delete node.dataset.autoContinuation;}
 return tracker.lastSpeaker;
}
export function projectDialogue(doc,cache=new Map()){
 const b=doc.project.frontstageWhiteboard;if(!b)return {flags:{},seeds:{}};
 let sceneID=null,tracker=new DialogueContinuation();const flags={},seeds={};
 const unused=new Set(b.layers.filter(l=>l.unused).map(l=>l.id)),inactive=new Set(b.blocks.filter(c=>unused.has(c.layerID)).map(c=>c.id));
 for(const beat of [...b.beats].sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id))){
  if(beat.omitted||inactive.has(beat.blockID))continue;
  if(sceneID!==beat.sceneID){sceneID=beat.sceneID;tracker=new DialogueContinuation();}
  seeds[beat.id]=tracker.lastSpeaker;flags[beat.id]=[];
  if(cache.get(beat.id)?.html!==beat.html){const root=globalThis.document.createElement('div');root.innerHTML=beat.html;cache.set(beat.id,{html:beat.html,lines:scriptParagraphs(root).map(n=>[paragraphKind(n),n.textContent])});}
  for(const[kind,text]of cache.get(beat.id).lines){const generated=tracker.observe(kind,text);if(kind==='character')flags[beat.id].push(generated);}
 }
 return {flags,seeds};
}
export function dialogueSeed(doc,beatID){return projectDialogue(doc).seeds[beatID]??null;}
