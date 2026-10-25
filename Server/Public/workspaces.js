import {createScriptFilter,mountScriptFilter,matchesScriptFilter,gapLabel} from './script-filter.js';
import { workspaceDesign as design } from './workspace-design.js';
import * as model from './workspace-model.js';
import { baminiPairs } from './bamini.js';
import { blockLocked } from './board-operations.js';
import { paginateParagraphs } from './pagination.js';
import { screenplayToolbar, sluglineFields, characterNames, elements, splitAtCaret } from './screenplay-editor.js';
const el=(tag,text,className)=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;if(className)e.className=className;return e;};
const $=id=>document.getElementById(id);
const download=(name,data,type='text/plain')=>{const url=URL.createObjectURL(new Blob([data],{type})),a=el('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
export function mountWorkspaces(api) {
  const scriptFilter=createScriptFilter();
  let mode='board',sceneID=null,roleID=null,actorID=null,revisionID=null,dayID=null,recordID=null,kind='research',search='',writing=false,projectID=null,paper='letter';
  const root=$('workspace-page'),selector=$('view-mode');
  const scriptDefaults={display:'Final Script',margin:'Full Margins',zoom:1,characters:true,tags:true,synopsis:false,boundaries:false,filter:''};
  let scriptView={...scriptDefaults},headingScene=null,activeEditor=null;const expandedBeats=new Set();
  try{const saved=JSON.parse(localStorage.getItem('frontstage-script-dedicated'));if(saved&&['Final Script','Content Only','Expand All','Collapse All','Index Cards'].includes(saved.display))scriptView={...scriptDefaults,...saved};}catch{}
  const scriptPreference=(key,value)=>{scriptView[key]=value;try{localStorage.setItem('frontstage-script-dedicated',JSON.stringify(scriptView));}catch{}render();};

  for(const p of design.pages){const o=el('option',p.title);o.value=p.id;selector.append(o);}
  const doc=()=>api.document(),state=()=>doc().project,scenes=()=>state().beats,currentScene=()=>scenes().find(s=>s.id===sceneID),readonly=()=>api.current()?.access==='reader';
  const change=(action,refresh=false)=>{writing=true;try{api.edit(()=>action(doc()));}finally{writing=false;}if(refresh)render();};
  const button=(text,action,write=false)=>{const b=el('button',text);if(write)b.disabled=readonly();b.onclick=()=>{try{action();}catch(e){api.status(e.message);}};return b;};
  const field=(name,value,action,type='text')=>{const label=el('label',name,'workspace-field'),input=el(type==='textarea'?'textarea':'input');input.setAttribute('aria-label',name);input.placeholder=name;if(type==='textarea')input.rows=1;if(type!=='textarea')input.type=type;input.value=value??'';input.disabled=readonly();input.onchange=()=>change(d=>action(input.type==='number'?Number(input.value):input.value,d));label.append(input);return label;};
  const toggle=(name,value,action)=>{const l=el('label',null,'workspace-toggle'),input=el('input');input.type='checkbox';input.checked=!!value;input.disabled=readonly();input.onchange=()=>change(d=>action(input.checked,d),true);l.append(input,document.createTextNode(name));return l;};
  const pick=(name,value,values,action,write=false)=>{const l=el('label',name,'workspace-field'),select=el('select');select.setAttribute('aria-label',name);for(const [key,text]of values){const o=el('option',text);o.value=key;select.append(o);}select.value=value??'';select.disabled=write&&readonly();select.onchange=()=>action(select.value);l.append(select);return l;};
  const empty=(title,body='')=>{const e=el('div',null,'workspace-empty');e.append(el('h2',title),el('p',body));return e;};
  const section=(title)=>{const s=el('section',null,'workspace-section');s.append(el('h2',title));return s;};
  const columns=()=>{const layout=el('div',null,'workspace-columns'),list=el('aside',null,'workspace-list'),detail=el('div',null,'workspace-detail');layout.append(list,detail);root.append(layout);return[list,detail];};
  function navigate(id){if(!design.pages.some(p=>p.id===id))return;mode=id;selector.value=id;render();}
  selector.onchange=()=>navigate(selector.value);
  $('scenes-toggle').textContent='Script';$('scenes-toggle').onclick=()=>{$('script').hidden=!$('script').hidden;};
  $('paper-mode').onchange=()=>{paper=$('paper-mode').value;let style=$('print-paper-size');if(!style){style=document.createElement('style');style.id='print-paper-size';document.head.append(style);}style.textContent=`@page { size: ${paper==='a4'?'A4':'letter'}; margin: 0; }`;render();};
  $('print-script').onclick=()=>{navigate('pages');requestAnimationFrame(()=>window.print());};
  $('add-scene').onclick=()=>{api.addScene();sceneID=api.selectedScene();render();};
  $('page-projects').onclick=()=>api.projects();
  function renderSidebar(){
    $('scene-sidebar').hidden=true;
  }

  function render(){
    if(!doc())return;
    if(projectID!==api.current()?.id){scriptFilter.clear();projectID=api.current()?.id;sceneID=api.selectedScene()??scenes()[0]?.id;roleID=actorID=revisionID=dayID=recordID=null;mode='board';selector.value=mode;}
    if(!scenes().some(s=>s.id===sceneID))sceneID=api.selectedScene()??scenes()[0]?.id;
    $('workspace').dataset.page=mode;$('workspace').classList.toggle('document-mode',mode!=='board');
    $('board-shell').hidden=mode!=='board';root.hidden=mode==='board';$('project-toolbar').hidden=false;
    renderSidebar();if(writing)return;root.replaceChildren();
    const title=design.pages.find(p=>p.id===mode).title;root.setAttribute('aria-label',title);document.title=`${doc().name||'Frontstage'} · ${title}`;
    try { ({edit:writePage,pages:pagesPage,revisions:revisionsPage,people:peoplePage,breakdown:breakdownPage,production:productionPage,writingTools:toolsPage,studio:studioPage,shared:sharedPage}[mode])?.(); }
    catch(e){root.replaceChildren(empty('This page could not be opened',e.message));api.status(e.message);}
  }
  function writePage(){
    activeEditor=null;
    const wrap=el('div',null,'writing-workspace');root.append(wrap);
    const tools=el('nav',null,'dedicated-script-tools');tools.setAttribute('aria-label','Script toolbar');wrap.append(tools);
    const menu=title=>{const detail=el('details'),summary=el('summary',title);detail.append(summary);tools.append(detail);detail.append(el('div',null,'script-menu-items'));return detail;};
    const option=(menu,title,run)=>{const b=button(title,()=>{run();menu.open=false;});b.onpointerdown=e=>e.preventDefault();menu.querySelector('.script-menu-items').append(b);return b;};
    const display=menu('Display');
    for(const value of ['Expand All','Index Cards','Collapse All','Content Only','Final Script'])option(display,value,()=>{expandedBeats.clear();scriptPreference('display',value);});
    for(const [key,label]of [['characters','Show Characters'],['tags','Show Tags'],['synopsis','Show Synopsis'],['boundaries','Show Block/Group Beginnings']])option(display,(scriptView[key]?'✓ ':'')+label,()=>scriptPreference(key,!scriptView[key]));
    for(const margin of ['Full Margins','Compact Margins','Squeezed','Super Squeezed'])option(display,margin,()=>scriptPreference('margin',margin));
    option(display,'Zoom In',()=>scriptPreference('zoom',Math.min(2,scriptView.zoom+.1)));option(display,'Zoom Out',()=>scriptPreference('zoom',Math.max(.5,scriptView.zoom-.1)));option(display,'100%',()=>scriptPreference('zoom',1));
    const styling=menu('Styling'),formatButtons=[];
    for(const kind of elements)formatButtons.push(option(styling,kind[0].toUpperCase()+kind.slice(1),()=>activeEditor?.format(kind)));
    for(const command of ['bold','italic','underline','strikeThrough'])formatButtons.push(option(styling,command,()=>activeEditor?.inline(command)));
    formatButtons.push(option(styling,'Split at Cursor',()=>activeEditor?.split()),option(styling,'Open Beat Editor',()=>activeEditor?.open()));
    const enableFormatting=enabled=>formatButtons.forEach(b=>b.disabled=!enabled);enableFormatting(false);
    const filter=menu('Filter');mountScriptFilter(filter.querySelector('.script-menu-items'),scriptFilter,{board:()=>model.board(doc()),scenes,selection:()=>new Set(api.selectedBeat()?[api.selectedBeat()]:[]),changed:()=>render()});
    const presets=menu('Presets');option(presets,'Reading',()=>{scriptView={...scriptDefaults};scriptPreference('display','Final Script');});option(presets,'Story Review',()=>scriptPreference('display','Expand All'));option(presets,'Index Cards',()=>scriptPreference('display','Index Cards'));
    const options=menu('Options');option(options,'Full Screen',()=>{if(document.fullscreenElement)document.exitFullscreen?.();else root.requestFullscreen?.();});option(options,'Writing Settings',()=>navigate('writingTools'));
    tools.append(el('span',scriptView.display,'script-mode-label'));
    const segments=model.scriptSegments(doc(),{includeInactive:true});if(!segments.length){wrap.append(empty('Your next story starts here','Add a scene or a beat to begin.'),button('Add Scene',()=>api.addScene(),true));return;}
    const desk=el('div',null,'continuous-desk'),sheet=el('div',null,'continuous-paper');desk.append(sheet);wrap.append(desk);applyTypography(sheet);sheet.dataset.display=scriptView.display;sheet.dataset.margin=scriptView.margin;sheet.style.zoom=scriptView.zoom;
    const plain=['Final Script','Content Only'].includes(scriptView.display);
    let filteredGap=[];
    for(const segment of segments){
      const s=segment.scene,beats=segment.beatIDs.map(id=>model.board(doc()).beats.find(b=>b.id===id)).filter(Boolean).filter(b=>matchesScriptFilter(b,model.board(doc()),scenes(),scriptFilter.state));
      if(segment.beatIDs.length&&!beats.length){filteredGap.push(...segment.beatIDs.map(id=>model.board(doc()).beats.find(b=>b.id===id)));continue;}
      if(scriptView.display!=='Index Cards'&&!scriptFilter.state.hideHeadings){
        const heading=el('button',`${segment.number}  ${model.heading(s)}${segment.continuation?' (CONTINUED)':''}`,'script-heading');heading.setAttribute('aria-label','Edit scene heading: '+model.heading(s));sheet.append(heading);
        heading.onclick=()=>{headingScene=headingScene===s.id?null:s.id;sceneID=s.id;render();};
        if(headingScene===s.id){const fields=el('div',null,'writing-scene-fields');fields.append(field('Scene title',s.title,(v,d)=>model.scene(d,s.id).title=v),field('Synopsis',s.summary,(v,d)=>model.scene(d,s.id).summary=v),sluglineFields(()=>model.scene(doc(),s.id),()=>scenes(),action=>change(()=>action(),true),!readonly()),button('Done',()=>{headingScene=null;render();}));sheet.append(fields);}
      }
      for(const beat of segment.beatIDs.map(id=>model.board(doc()).beats.find(b=>b.id===id)).filter(Boolean)){
        if(!beats.includes(beat)){filteredGap.push(beat);continue;}
        if(filteredGap.length&&!scriptFilter.state.hideGaps)sheet.append(el('div',gapLabel(filteredGap,scriptFilter.state.gaps),'script-filter-gap'));filteredGap=[];
        const id=beat.id,block=el('section',null,'script-snippet');block.dataset.scriptBeatID=id;
        const owner=model.board(doc()).blocks.find(b=>b.id===beat.blockID),unused=model.board(doc()).layers.find(l=>l.id===owner?.layerID)?.unused;if(unused||beat.omitted||s.isDisabled)block.append(el('div',unused?'Unused lane · excluded from export':'Disabled beat · excluded from export','script-beat-status'));
        if(!plain){const isExpanded=(scriptView.display!=='Collapse All')!==expandedBeats.has(id),name=button((isExpanded?'▾ ':'▸ ')+beat.title,()=>{if(expandedBeats.has(id))expandedBeats.delete(id);else expandedBeats.add(id);const text=block.querySelector('.script-text');if(text){text.hidden=!text.hidden;name.textContent=(text.hidden?'▸ ':'▾ ')+beat.title;}});name.className='snippet-heading';name.ondblclick=()=>api.openBeat(id);block.append(name);
          if(scriptView.display!=='Index Cards'){if(scriptView.characters&&beat.characters.length)block.append(el('div',beat.characters.join(' · '),'script-beat-details'));if(scriptView.tags&&beat.tags.length)block.append(el('div',beat.tags.join(' · '),'script-beat-details'));}
          if(scriptView.synopsis||scriptView.display==='Index Cards')block.append(el('div',beat.synopsis||'','script-beat-details'));
          if(!scriptFilter.state.hideBreaks&&scriptView.boundaries){const owner=model.board(doc()).blocks.find(b=>b.id===beat.blockID);if(owner&&!owner.standalone&&model.board(doc()).beats.filter(b=>b.blockID===owner.id).sort((a,b)=>a.order-b.order)[0]?.id===id)block.prepend(el('div',owner.name,'script-beat-details'));}
        }
        if(scriptView.display!=='Index Cards'){
          const text=el('div',null,'script-text');text.contentEditable=!(readonly()||s.frontstageTextLocked||beat.locked||blockLocked(model.board(doc()),beat.blockID));text.setAttribute('role','textbox');text.setAttribute('aria-label',`Script: ${beat.title}`);text.innerHTML=api.cleanHTML(beat.html);text.dataset.beatId=id;text.hidden=!plain&&((scriptView.display==='Collapse All')!==expandedBeats.has(id));
          const changed=()=>{if(text.isComposing)return;change(d=>{const target=model.board(d).beats.find(b=>b.id===id);if(target)target.html=api.cleanHTML(text.innerHTML);});};
          text.oncompositionstart=()=>text.isComposing=true;text.oncompositionend=()=>{text.isComposing=false;changed();};text.oninput=changed;
          const behavior=screenplayToolbar(text,changed,text.contentEditable==='true',()=>characterNames(doc())).editor;
          behavior.split=()=>{const [first,last]=splitAtCaret(text);change(d=>model.splitBeat(d,id,first,last),true);};behavior.open=()=>api.openBeat(id);
          text.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'&&!e.isComposing){e.preventDefault();try{behavior.split();}catch(error){api.status(error.message);}}});
          text.onfocus=()=>{activeEditor=behavior;enableFormatting(text.isContentEditable);};
          text.oncontextmenu=e=>{e.preventDefault();activeEditor=behavior;enableFormatting(text.isContentEditable);behavior.remember();styling.open=true;};
          block.append(text);
        }sheet.append(block);
      }
      if(!segment.beatIDs.length){const p=el('div',null,'script-text');p.innerHTML=api.cleanHTML(segment.html);sheet.append(p);}
    }
  }
  function applyTypography(node){const t=state().frontstageScriptLayout||{};node.style.setProperty('--script-font',t.fontName||'Courier');node.style.setProperty('--script-size',`${t.fontSize||12}px`);node.style.setProperty('--script-line',`${t.lineHeight||14}px`);node.style.setProperty('--script-spacing',`${t.paragraphSpacing??10}px`);}
  function pagesPage(){
    const top=el('div',null,'page-heading');top.append(el('h1','Pages'),button('Print / Export PDF',()=>window.print()));root.append(top);
    const desk=el('div',null,'pages-desk');root.append(desk);const width=paper==='a4'?595.2756:612,height=paper==='a4'?841.8898:792;
    const makePage=()=>{const page=el('article',null,'paper-sheet');page.style.width=width+'px';page.style.height=height+'px';page.dataset.paper=paper;applyTypography(page);const number=el('div',String(desk.children.length+1),'paper-number'),content=el('div',null,'page-content script-text');page.append(number,content);desk.append(page);return content;};
    const nodes=[];
    for(const segment of model.scriptSegments(doc())){
      nodes.push({node:el('p',`${segment.number}  ${model.heading(segment.scene)}${segment.continuation?' (CONTINUED)':''}`,'sc-line sc-slugline'),newPage:segment.scene.frontstagePageStart&&!segment.continuation});
      const source=el('div');source.innerHTML=api.cleanHTML(segment.html);
      for(const node of [...source.childNodes])nodes.push({node:node.nodeType===1?node:el('p',node.textContent)});
    }
    paginateParagraphs(makePage,nodes,height-144);
    if(!model.scriptSegments(doc()).length){desk.remove();root.append(empty('No screenplay pages','Add an active scene to preview the screenplay.'));}
    top.append(el('span',`${desk.children.length} pages · ${paper==='a4'?'A4':'US Letter'}`));
  }
  function revisionsPage(){
    const s=currentScene();if(!s){root.append(empty('Select a scene'));return;}const[list,detail]=columns();list.append(el('h2',`Revisions · ${s.title}`));
    let name='';list.append(field('Revision name','',v=>name=v),button('Capture Revision',()=>change(d=>revisionID=model.captureRevision(d,s.id,name),true),true));
    for(const r of [...(s.versions||[])].reverse()){const b=button(r.frontstageLabel||r.title||'Revision',()=>{revisionID=r.id;render();});b.classList.toggle('selected',r.id===revisionID);list.append(b);}
    const r=s.versions?.find(v=>v.id===revisionID);if(!r){detail.append(empty('Select a revision','Capture a named snapshot to compare or restore it later.'));return;}
    detail.append(el('h2',`${r.frontstageLabel||r.title} → Current text`),el('p','− removed from revision   + added in current text'));
    const before=api.plain(r.content).split('\n'),after=api.plain(s.content).split('\n'),diff=el('pre',null,'revision-diff');
    let i=0,j=0;while(i<before.length||j<after.length){if(before[i]===after[j]&&i<before.length){diff.append(el('div','  '+before[i]));i++;j++;}else{if(i<before.length)diff.append(el('div','− '+before[i++],'removed'));if(j<after.length)diff.append(el('div','+ '+after[j++],'added'));}}
    detail.append(diff,button('Restore Selected Revision',()=>change(d=>model.restoreRevision(d,s.id,r.id),true),true),el('p','Restoring first captures a backup of the current scene. Other production data stays current.'));
  }
  function peoplePage(){
    const[list,detail]=columns(),roles=Object.entries(state().characterData||{}).sort((a,b)=>(a[1].name||a[0]).localeCompare(b[1].name||b[0]));list.append(el('h2','Characters & Casting'));let name='';list.append(field('New character','',v=>name=v),button('Add',()=>change(d=>roleID=model.createCharacter(d,name),true),true));
    list.append(button('Discover From Script',()=>change(d=>{for(const s of d.project.beats){const div=el('div');div.innerHTML=api.cleanHTML(s.content);for(const cue of div.querySelectorAll('.sc-character')){const name=cue.textContent.replace(/\s*\((?:CONT'D|V\.O\.|O\.S\.)\)/gi,'').trim().toUpperCase();if(!name)continue;let key=Object.keys(d.project.characterData||{}).find(k=>k.toUpperCase()===name||(d.project.characterData[k].name||'').toUpperCase()===name);if(!key)key=model.createCharacter(d,name);model.assignCharacter(d,s.id,key,true);}}},true),true));
    if(!roles.some(([id])=>id===roleID))roleID=roles[0]?.[0];for(const[id,r]of roles){const b=button(r.name||id,()=>{roleID=id;actorID=null;render();});b.classList.toggle('selected',id===roleID);list.append(b);}
    const role=state().characterData?.[roleID];if(!role){detail.append(empty('Add or select a character','Discover character cues from the screenplay or add a role manually.'));return;}
    detail.append(el('h1',role.name));for(const key of model.characterFields)detail.append(field(model.label(key),role[key],(v,d)=>d.project.characterData[roleID][key]=v,'textarea'));
    detail.append(el('h2','Casting Options'));let actor='';detail.append(field('Actor name','',v=>actor=v),button('Add Option',()=>change(d=>actorID=model.addActor(d,roleID,actor),true),true));
    for(const a of role.artists||[]){const b=button(`${role.confirmedArtistId===a.id?'✓ ':''}${a.name} · ${model.label(a.status||'idea')}`,()=>{actorID=a.id;render();});detail.append(b);}
    const actorRecord=role.artists?.find(a=>a.id===actorID);if(actorRecord){const update=(key,value,d)=>{const a=d.project.characterData[roleID].artists.find(a=>a.id===actorID);if(['email','phone'].includes(key))(a.contact||={})[key]=value;else a[key]=value;};
      detail.append(el('h2',actorRecord.name),pick('Status',actorRecord.status,model.castingStatuses.map(x=>[x,model.label(x)]),v=>change(d=>{update('status',v,d);if(v==='passed'&&d.project.characterData[roleID].confirmedArtistId===actorID)delete d.project.characterData[roleID].confirmedArtistId;},true),true));
      for(const key of ['email','phone','notes'])detail.append(field(model.label(key),key==='notes'?actorRecord.notes:actorRecord.contact?.[key],(v,d)=>update(key,v,d),key==='notes'?'textarea':'text'));
      detail.append(button('Confirm for Role',()=>change(d=>model.confirmActor(d,roleID,actorID),true),true),button('Clear Confirmation',()=>change(d=>model.confirmActor(d,roleID,null),true),true));}
  }
  function breakdownPage(){const s=currentScene();if(!s){root.append(empty('Select a scene'));return;}const body=section(`Breakdown · ${s.title}`);root.append(body);body.append(el('p',model.heading(s)),el('h3','Characters in this scene'));
    for(const[key,r]of Object.entries(state().characterData||{}))body.append(toggle(r.name||key,s.characters?.includes(key),(v,d)=>model.assignCharacter(d,s.id,key,v)));
    body.append(el('h3','Production Requirements'));let category='PROPS',name='',count=1,notes='';body.append(pick('Category',category,model.categories.map(x=>[x,model.label(x)]),v=>category=v),field('Item name','',v=>name=v),field('Quantity',count,v=>count=v,'number'),field('Requirement notes','',v=>notes=v),button('Add Requirement',()=>change(d=>model.addRequirement(d,s.id,category,name,count,notes),true),true));
    for(const item of model.breakdownEntries(s)){const card=el('div',null,'workspace-card'),update=(key,v,d)=>{const values=model.scene(d,s.id)[item.storage][item.bucket];const value=values[item.index];values[item.index]=typeof value==='string'?{name:value}:value;values[item.index][key]=v;};card.append(el('h3',model.label(item.category||item.bucket)),field('Name',item.name,(v,d)=>{if(!v.trim())throw Error('An item needs a name.');update('name',v,d);}),field('Count',item.count||1,(v,d)=>{if(!Number.isInteger(v)||v<1||v>100000)throw Error('Choose a positive quantity.');update('count',v,d);},'number'),field('Notes',item.description,(v,d)=>update('description',v,d)),button('Remove Requirement',()=>change(d=>model.scene(d,s.id)[item.storage][item.bucket].splice(item.index,1),true),true));body.append(card);}
  }
  function productionPage(){const[list,detail]=columns(),p=state().frontstageProduction||{days:[]},days=p.days||[];list.append(el('h2','Shooting Days'));let date=new Date().toISOString().slice(0,10);list.append(field('Shoot date',date,v=>date=v,'date'),button('Add Day',()=>change(d=>dayID=model.addDay(d,date),true),true),button('Export Schedule CSV',()=>download('Schedule.csv',model.csv(model.scheduleRows(doc())),'text/csv')),button('Export Breakdown CSV',()=>download('Breakdown.csv',model.csv(model.breakdownRows(doc())),'text/csv')),button('Export Day Out of Days',()=>download('Day Out of Days.csv',model.csv(model.dayOutRows(doc())),'text/csv')));
    if(!days.some(d=>d.id===dayID))dayID=days[0]?.id;for(const d of days)list.append(button(`Day ${d.number} · ${d.date}`,()=>{dayID=d.id;render();}));const day=days.find(d=>d.id===dayID);if(!day){detail.append(empty('Plan a shooting day','Create a day, assign scenes, and prepare its crew and cast calls.'));return;}
    const update=(key,v,d)=>model.production(d).days.find(d=>d.id===dayID)[key]=v;
    detail.append(el('h1',`Day ${day.number}`),button('Call Sheet / Print',()=>printReport(day)),field('Shoot Date',day.date,(v,d)=>update('date',v,d),'date'),field('Crew Call',day.callTime,(v,d)=>update('callTime',v,d),'time'),field('Estimated Wrap',day.wrapTime,(v,d)=>update('wrapTime',v,d),'time'));
    for(const warning of model.scheduleWarnings(doc(),day))detail.append(el('p',warning,'warning'));
    detail.append(el('h2','Scenes and estimates'));for(const s of scenes().filter(s=>!s.isDisabled)){const row=el('div',null,'workspace-row');row.append(toggle(s.title,day.sceneIDs.includes(s.id),(v,d)=>model.assignDay(d,s.id,v?dayID:null)),field(`Minutes: ${s.title}`,p.sceneEstimates?.[s.id]??60,(v,d)=>{if(!Number.isInteger(v)||v<1||v>1440)throw Error('Choose an estimate from 1 to 1440 minutes.');(model.production(d).sceneEstimates||={})[s.id]=v;},'number'));detail.append(row);}
    detail.append(el('h2','Shooting order'));for(const id of day.sceneIDs){const row=el('div',null,'workspace-row');row.append(el('span',scenes().find(s=>s.id===id)?.title||`Missing scene ${id}`));for(const[title,offset]of[['Move up',-1],['Move down',1]])row.append(button(title,()=>change(d=>{const ids=model.production(d).days.find(d=>d.id===dayID).sceneIDs,i=ids.indexOf(id),j=i+offset;if(j>=0&&j<ids.length)[ids[i],ids[j]]=[ids[j],ids[i]];},true),true));detail.append(row);}
    detail.append(el('h2','Location, safety and crew'));for(const[key,title]of Object.entries(model.productionFields))detail.append(field(title,day[key],(v,d)=>update(key,v,d),key==='notes'?'textarea':'text'));
    detail.append(el('h2','Cast calls'));const keys=[...new Set(day.sceneIDs.flatMap(id=>scenes().find(s=>s.id===id)?.characters||[]))];for(const key of keys){const card=section(state().characterData?.[key]?.name||key);for(const[k,title]of[['pickupTime','Pickup'],['makeupTime','Makeup'],['onSetTime','On Set'],['notes','Notes']])card.append(field(title,day.castCalls?.[key]?.[k],(v,d)=>{const day=model.production(d).days.find(x=>x.id===dayID);day.castCalls||={};if(!Object.hasOwn(day.castCalls,key))Object.defineProperty(day.castCalls,key,{value:{},writable:true,enumerable:true,configurable:true});day.castCalls[key][k]=v;},k==='notes'?'text':'time'));detail.append(card);}
  }
  function printReport(day){const overlay=el('section',null,'report-preview');overlay.id='report-preview';const close=button('Close',()=>overlay.remove()),print=button('Print / Save PDF',()=>window.print());overlay.append(close,print,el('h1',`${doc().name} · Day ${day.number} Call Sheet`),el('p',`${day.date} · Crew call ${day.callTime} · Wrap ${day.wrapTime}`));for(const[k,title]of Object.entries(model.productionFields))if(day[k])overlay.append(el('h3',title),el('p',day[k]));for(const id of day.sceneIDs){const s=scenes().find(s=>s.id===id);if(s&&!s.isDisabled){overlay.append(el('h3',s.title),el('p',model.heading(s)));for(const item of model.breakdownEntries(s))overlay.append(el('p',`${model.label(item.category||item.bucket)}: ${item.name} ×${item.count||1} ${item.description||''}`));}}for(const[key,call]of Object.entries(day.castCalls||{}))overlay.append(el('h3',key),el('p',Object.entries(call).map(([k,v])=>`${model.label(k)}: ${v}`).join(' · ')));for(const warning of model.scheduleWarnings(doc(),day))overlay.append(el('p',warning));document.body.append(overlay);}
  function toolsPage(){const body=section('Writing Tools');root.append(body);const s=currentScene();if(s){const group=section('Scene script');group.append(el('h3',s.title),toggle('Lock script text and heading',s.frontstageTextLocked,(v,d)=>model.scene(d,s.id).frontstageTextLocked=v),toggle('Start this scene on a new page',s.frontstagePageStart,(v,d)=>model.scene(d,s.id).frontstagePageStart=v));body.append(group);}
    const typography={fontName:'Courier',fontSize:12,lineHeight:14,paragraphSpacing:10,...state().frontstageScriptLayout},group=section('Screenplay typography');for(const[key,title]of[['fontName','Font name'],['fontSize','Font size'],['lineHeight','Line height'],['paragraphSpacing','Paragraph spacing']])group.append(field(title,typography[key],(v,d)=>{const value={...typography,...d.project.frontstageScriptLayout,[key]:v};if(key==='fontSize')value.lineHeight=Math.max(v,value.lineHeight);model.setTypography(d,value);},key==='fontName'?'text':'number'));body.append(group);
    const tamil=section('Bamini → Unicode Tamil'),input=el('textarea'),output=el('pre');input.setAttribute('aria-label','Bamini text');input.oninput=()=>{let result=input.value;for(const[a,b]of baminiPairs)result=result.split(a).join(b);output.textContent=result.normalize('NFC');};tamil.append(el('p','Paste Bamini text explicitly. English letters in the input will be converted too.'),input,output,button('Copy Unicode',()=>navigator.clipboard.writeText(output.textContent).catch(e=>api.status(e.message))));body.append(tamil);
    const parallel=section('Two-column script / translation');if(s){parallel.append(el('h3',s.title));for(const row of s.frontstageParallel||[]){const pair=el('div',null,'parallel-row');for(const key of ['left','right'])pair.append(field(key==='left'?'Original':'Translation',row[key],(v,d)=>model.scene(d,s.id).frontstageParallel.find(r=>r.id===row.id)[key]=v,'textarea'));pair.append(button('Remove Row',()=>change(d=>model.scene(d,s.id).frontstageParallel=model.scene(d,s.id).frontstageParallel.filter(r=>r.id!==row.id),true),true));parallel.append(pair);}parallel.append(button('Add Row',()=>change(d=>(model.scene(d,s.id).frontstageParallel||=[]).push({id:crypto.randomUUID(),left:'',right:''}),true),true),button('Print Two-column Script',()=>{const overlay=el('section',null,'report-preview');overlay.id='report-preview';overlay.append(button('Close',()=>overlay.remove()),button('Print / Save PDF',()=>window.print()),el('h1',s.title));for(const row of s.frontstageParallel||[]){const pair=el('div',null,'parallel-row');pair.append(el('p',row.left),el('p',row.right));overlay.append(pair);}document.body.append(overlay);}));}else parallel.append(empty('Select a scene'));body.append(parallel);
  }
  function studioPage(){const[list,detail]=columns(),s=state().frontstageStudio||{records:[],assets:[]};list.append(pick('Workspace',kind,Object.keys(model.studioFields).map(k=>[k,k==='shot'?'Shots & Storyboards':model.label(k)]),v=>{kind=v;recordID=null;render();}));const searchField=field('Search records',search,v=>{search=v;render();});searchField.querySelector('input').disabled=false;list.append(searchField);
    const records=s.records.filter(r=>r.kind===kind&&`${r.title} ${r.body}`.toLowerCase().includes(search.toLowerCase()));if(!records.some(r=>r.id===recordID))recordID=records[0]?.id;for(const r of records)list.append(button(r.title,()=>{recordID=r.id;render();}));list.append(button('Add',()=>change(d=>{recordID=model.addRecord(d,kind,sceneID);const beatID=api.selectedBeat();if(beatID)model.studio(d).records.find(r=>r.id===recordID).beatID=beatID;},true),true),button('Export CSV',()=>download(`${kind}.csv`,model.csv([['ID','Title','Scene','Beat','Notes','Details','Attachments'],...records.map(r=>[r.id,r.title,r.sceneID,r.beatID,r.body,Object.entries(r.fields).map(([k,v])=>`${k}: ${v}`).join('; '),r.assetIDs.map(id=>s.assets.find(a=>a.id===id)?.filename).join('; ')])]),'text/csv')));
    const record=records.find(r=>r.id===recordID);if(!record){detail.append(empty('Add or select a record'));return;}const update=(key,value,d)=>model.studio(d).records.find(r=>r.id===recordID)[key]=value;
    detail.append(field('Title',record.title,(v,d)=>update('title',v,d)),pick('Linked scene',record.sceneID??'',[['','No scene'],...scenes().map(s=>[s.id,s.title])],v=>change(d=>{if(v==='')delete model.studio(d).records.find(r=>r.id===recordID).sceneID;else update('sceneID',Number(v),d);},true),true),field('Notes',record.body,(v,d)=>update('body',v,d),'textarea'));
    if(record.beatID)detail.append(button('Show linked beat',()=>{navigate('board');api.selectBeat(record.beatID);}));for(const key of model.studioFields[kind])detail.append(field(key,record.fields[key],(v,d)=>model.studio(d).records.find(r=>r.id===recordID).fields[key]=v));detail.append(el('h2','Attachments / Storyboard Frames'));
    for(const asset of s.assets.filter(a=>record.assetIDs.includes(a.id))){const card=el('div',null,'workspace-card');if(/\.(png|jpe?g|gif|webp)$/i.test(asset.filename)){const image=el('img');image.alt=asset.filename;image.src=`data:image/${/\.png$/i.test(asset.filename)?'png':/\.gif$/i.test(asset.filename)?'gif':/\.webp$/i.test(asset.filename)?'webp':'jpeg'};base64,${asset.data}`;card.append(image);}card.append(el('span',asset.filename),button('Export Attachment',()=>download(asset.filename,Uint8Array.from(atob(asset.data),c=>c.charCodeAt(0)),'application/octet-stream')),button('Remove Attachment',()=>change(d=>model.removeStudioAsset(d,record.id,asset.id),true),true));detail.append(card);}
    const attach=field('Attach files','',()=>{},'file'),input=attach.querySelector('input');input.multiple=true;input.onchange=async()=>{for(const file of input.files){if(file.size>10*1024*1024){api.status('Attachments allow 10 MB per file.');continue;}const project=api.current()?.id,owner=recordID,reader=new FileReader();reader.onload=()=>{if(api.current()?.id!==project)return;change(d=>model.addAttachment(d,owner,file.name,String(reader.result).split(',')[1]),true);};reader.readAsDataURL(file);}};detail.append(attach,el('p','Attachments travel inside the project. Limit: 10 MB per file, 64 MB total.'),button('Delete Record',()=>change(d=>model.removeStudioRecord(d,record.id),true),true));
  }
  function sharedPage(){const body=section('Shared Projects');root.append(body);const current=api.current();if(current?.local){body.append(el('p','This project is saved on this device.'),button('Download Local Backup',()=>api.download()),button('Connect to Shared Server',()=>api.connect()));return;}
    body.append(el('p',`${current.name||doc().name} · ${current.access} · revision ${current.revision}`),button('Refresh Projects',()=>api.projects()),button('Synchronize Local Changes',()=>api.sync()),button('Get Latest Changes',()=>api.refresh().catch(e=>api.status(e.message))),button('Download Local Backup',()=>api.download()),button('Create Shared Copy',()=>api.duplicate().catch(e=>api.status(e.message))));
    if(current.access==='owner'){let member='',access='editor';body.append(field('Registered username','',v=>member=v),pick('Project access',access,[['editor','Editor'],['reader','Reader'],['remove','Remove access']],v=>access=v),button('Update Access',()=>api.share(member,access).catch(e=>api.status(e.message))));}
    body.append(el('p','Keep saving locally while disconnected. Conflicting edits retain a downloadable local copy.'));
  }
  return {render,navigate,scene:()=>sceneID,selectScene:id=>{sceneID=id;render();},isWriting:()=>writing};
}
