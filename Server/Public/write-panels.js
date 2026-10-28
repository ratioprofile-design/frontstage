import {annotationIDs} from './script-annotations.js';
import {isSceneModel,conversionGroups,convertSceneCopy,updateBeatCard,duplicateBeat} from './scene-model.js';
import {reorderTimelineBeats,blockLocked} from './board-operations.js';
import {attachLiveMarkdown} from './live-markdown.js';
import {pullOutBeats,replaceDocument} from './script-inclusion.js';
import * as model from './workspace-model.js';
import * as data from './write-panel-model.js';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;if(cls)e.className=cls;return e;};
export function mountWritePanels(host,center,api) {
  let pref={left:280,right:320,leftOpen:true,rightOpen:true,leftTab:'Scenes',rightTab:'Notes',scope:'Scene'};
  try{pref={...pref,...JSON.parse(localStorage.getItem('frontstage-write-panels')||'{}')};}catch{}
  pref.left=Math.max(220,Math.min(480,Number(pref.left)||280));pref.right=Math.max(260,Math.min(480,Number(pref.right)||320));
  const save=()=>localStorage.setItem('frontstage-write-panels',JSON.stringify(pref));
  const layout=el('div',null,'write-panel-layout'),left=el('aside',null,'write-panel write-left'),right=el('aside',null,'write-panel write-right'),bar=el('nav',null,'write-panel-switches');
  host.append(layout);layout.append(left,center,right);center.classList.add('write-center');
  center.querySelector('.dedicated-script-tools').append(bar);
  let drawer=null,drawerOpener=null,drawerRange=null,announcedDrawer=null,revealTarget=null,revealFrame=null,pendingNavigation=null;
  left.id='write-scenes-panel';right.id='write-inspector-panel';
  left.setAttribute('aria-label','Scenes and locations');right.setAttribute('aria-label','Writing inspector');
  const backdrop=el('button',null,'write-drawer-backdrop');backdrop.type='button';backdrop.tabIndex=-1;backdrop.hidden=true;backdrop.setAttribute('aria-label','Close writing panel');layout.append(backdrop);
  const announcement=el('span',null,'write-drawer-announcement');announcement.setAttribute('role','status');announcement.setAttribute('aria-live','polite');announcement.setAttribute('aria-atomic','true');layout.append(announcement);
  const scenesToggle=document.getElementById('scenes-toggle'),oldControls=scenesToggle?.getAttribute('aria-controls'),oldExpanded=scenesToggle?.getAttribute('aria-expanded');
  const isOverlay=side=>window.matchMedia(side==='left'?'(max-width:899px)':'(max-width:1179px)').matches;
  let current=api.selection(),search='',breakdownSearch='',expanded=new Set(),quote='',quoteScene=null;
  const run=action=>{try{return action();}catch(e){api.status(e.message);}};
  const button=(title,action,write=false)=>{const b=el('button',title);b.type='button';b.disabled=write&&api.readonly();b.onclick=()=>run(action);return b;};
  const mutate=(action,refresh=true)=>{api.change(action);if(refresh)refreshPanels();};
  const scene=()=>api.document().project.beats.find(s=>s.id===current.sceneID);
  const input=(label,value,change,multiline=false)=>{const field=el('label',label),i=el(multiline?'textarea':'input');i.value=value??'';i.setAttribute('aria-label',label);i.disabled=api.readonly();i.onchange=()=>run(()=>change(i.value));field.append(i);return field;};
  const select=(label,value,options,change)=>{const field=el('label',label),s=el('select');s.setAttribute('aria-label',label);for(const option of options){const o=el('option',option);o.value=option;s.append(o);}s.value=value;s.onchange=()=>run(()=>change(s.value));field.append(s);return field;};
  function widths(){
    if(drawer&&!isOverlay(drawer)){
      const panel=drawer==='left'?left:right,restore=drawerOpener,headerFocused=panel.querySelector('.write-drawer-header')?.contains(document.activeElement);
      drawer=null;drawerRange=null;drawerOpener=null;
      if(headerFocused&&restore?.isConnected)queueMicrotask(()=>restore.focus({preventScroll:true}));
    }
    layout.style.setProperty('--write-left',pref.left+'px');layout.style.setProperty('--write-right',pref.right+'px');layout.dataset.left=String(isOverlay('left')?drawer==='left':pref.leftOpen);layout.dataset.right=String(isOverlay('right')?drawer==='right':pref.rightOpen);
    const viewport=window.visualViewport,bounds=layout.getBoundingClientRect(),visibleTop=viewport?.offsetTop||0,visibleLeft=viewport?.offsetLeft||0,visibleHeight=viewport?.height||window.innerHeight,visibleWidth=viewport?.width||window.innerWidth;
    let top=Math.max(bounds.top,visibleTop),bottom=Math.min(bounds.bottom,visibleTop+visibleHeight);
    if(bottom-top<96){top=visibleTop;bottom=visibleTop+visibleHeight;}
    const edge=Math.max(bounds.left,visibleLeft),end=Math.min(bounds.right,visibleLeft+visibleWidth);
    for(const[key,value]of Object.entries({top,left:edge,right:Math.max(0,document.documentElement.clientWidth-end),height:Math.max(0,bottom-top),width:Math.max(0,end-edge)}))layout.style.setProperty('--write-drawer-'+key,value+'px');
    center.inert=!!drawer;backdrop.hidden=!drawer;backdrop.setAttribute('aria-label',drawer==='left'?'Close scenes panel':'Close inspector');
    for(const[panel,side]of[[left,'left'],[right,'right']]){
      panel.dataset.drawerMode=String(isOverlay(side));panel.inert=!!drawer&&drawer!==side;
      panel.setAttribute('role',drawer===side?'dialog':'complementary');panel.setAttribute('aria-hidden',String(layout.dataset[side]!=='true'));
      if(drawer===side){panel.setAttribute('aria-modal','true');panel.setAttribute('aria-labelledby',panel.id+'-title');}else{panel.removeAttribute('aria-modal');panel.removeAttribute('aria-labelledby');}
    }
    scenesToggle?.setAttribute('aria-controls',left.id);scenesToggle?.setAttribute('aria-expanded',layout.dataset.left);inspectorToggle.setAttribute('aria-controls',right.id);inspectorToggle.setAttribute('aria-expanded',layout.dataset.right);
    if(drawer!==announcedDrawer){announcement.textContent=drawer?(drawer==='left'?'Scenes panel opened.':'Inspector opened.'):'Writing panel closed.';announcedDrawer=drawer;}
    if(revealTarget){cancelAnimationFrame(revealFrame);revealFrame=requestAnimationFrame(()=>{if(center.isConnected&&revealTarget)api.recenter?.(revealTarget.sceneID,revealTarget.beatID);});}
  }
  function closeDrawer(restoreFocus=true){
    if(!drawer)return;
    const active=drawer==='left'?left:right;if(active.contains(document.activeElement))document.activeElement.blur();
    drawer=null;left.style.removeProperty('--drawer-drag');right.style.removeProperty('--drawer-drag');widths();
    if(restoreFocus){if(drawerRange&&center.contains(drawerRange.startContainer)){const selection=getSelection();selection.removeAllRanges();selection.addRange(drawerRange);}drawerRange=null;if(drawerOpener?.isConnected)drawerOpener.focus({preventScroll:true});}drawerOpener=null;
  }
  function toggle(side){
    if(isOverlay(side)){
      if(drawer===side){closeDrawer();return;}
      const selection=getSelection();if(selection?.rangeCount&&center.contains(selection.anchorNode))drawerRange=selection.getRangeAt(0).cloneRange();
      closeDrawer(false);drawer=side;drawerOpener=side==='left'?scenesToggle:inspectorToggle;widths();
      (side==='left'?left:right).querySelector('.write-drawer-close').focus({preventScroll:true});
    }else{pref[side+'Open']=!pref[side+'Open'];save();widths();}
  }
  const inspectorToggle=button('Inspector',()=>toggle('right'));inspectorToggle.setAttribute('aria-label','Notes / Breakdown / History');bar.append(inspectorToggle);
  backdrop.onclick=()=>closeDrawer();
  for(const[panel,side,title]of[[left,'left','Scenes'],[right,'right','Inspector']]){
    const header=el('div',null,'write-drawer-header'),heading=el('strong',title),close=button('×',()=>closeDrawer());heading.id=panel.id+'-title';close.className='write-drawer-close';close.setAttribute('aria-label',side==='left'?'Close scenes panel':'Close inspector');
    const grip=el('span','↔','write-drawer-grip');grip.setAttribute('aria-hidden','true');header.append(grip,heading,close);panel.append(header);
    let swipe=null;
    const reset=()=>{swipe=null;delete panel.dataset.swiping;panel.style.removeProperty('--drawer-drag');};
    header.onpointerdown=event=>{if(drawer!==side||event.isPrimary===false||event.button!==0||event.target.closest('button'))return;event.preventDefault();swipe={id:event.pointerId,x:event.clientX,y:event.clientY};header.setPointerCapture(event.pointerId);};
    header.onpointermove=event=>{if(!swipe||event.pointerId!==swipe.id)return;const dx=event.clientX-swipe.x,dy=event.clientY-swipe.y,direction=side==='right'?1:-1;if(dx*direction>0&&Math.abs(dx)>Math.abs(dy)*1.5){panel.dataset.swiping='true';panel.style.setProperty('--drawer-drag',dx+'px');}};
    header.onpointerup=event=>{if(!swipe||event.pointerId!==swipe.id)return;const dx=event.clientX-swipe.x,dy=event.clientY-swipe.y,close=dx*(side==='right'?1:-1)>=64&&Math.abs(dx)>Math.abs(dy)*1.5;reset();if(close)closeDrawer();};
    header.onpointercancel=reset;header.onlostpointercapture=reset;
  }
  for(const [panel,side]of[[left,'left'],[right,'right']]){const handle=el('div',null,'write-resizer');handle.tabIndex=0;handle.setAttribute('role','separator');handle.setAttribute('aria-label','Resize '+side+' panel');handle.onkeydown=e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();pref[side]=Math.max(side==='left'?220:260,Math.min(480,pref[side]+(e.key==='ArrowRight'?10:-10)*(side==='left'?1:-1)));save();widths();}};handle.onpointerdown=e=>{e.preventDefault();const start=e.clientX,width=pref[side];handle.setPointerCapture(e.pointerId);handle.onpointermove=event=>{pref[side]=Math.max(side==='left'?220:260,Math.min(480,width+(event.clientX-start)*(side==='left'?1:-1)));widths();};handle.onpointerup=()=>{handle.onpointermove=null;save();};};panel.append(handle);}
  const leftBody=el('div',null,'write-panel-body'),rightBody=el('div',null,'write-panel-body');left.append(leftBody);right.append(rightBody);
  function tabs(body,values,key){const row=el('nav');for(const value of values){const b=button(value,()=>{pref[key]=value;save();refreshPanels();});b.setAttribute('aria-pressed',String(pref[key]===value));row.append(b);}body.append(row);}
  function navigate(card,beatID=card.beats[0]?.id){
    if(center.querySelector('.continuous-editor')?.isComposing){pendingNavigation={card,beatID};return;}
    const found=api.reveal(card.scene.id,beatID);
    if(!found){const notice=el('div',null,'write-reveal');notice.append(el('p','This beat is hidden by screenplay filters.'),button('Reset filters and reveal',()=>api.resetReveal(card.scene.id,beatID)));leftBody.prepend(notice);return;}
    revealTarget={sceneID:card.scene.id,beatID};
    if(drawer==='left'){const target=center.querySelector('[data-beat-id="'+CSS.escape(beatID)+'"],[data-script-beat-id="'+CSS.escape(beatID)+'"]');if(target){drawerRange=document.createRange();drawerRange.selectNodeContents(target);drawerRange.collapse(true);}}
    current={sceneID:card.scene.id,beatID};refreshMetadata();renderRight();
  }
  function finishComposition(){if(pendingNavigation)queueMicrotask(()=>{if(!center.isConnected||!pendingNavigation)return;const {card,beatID}=pendingNavigation;pendingNavigation=null;navigate(card,beatID);});}
  function clearReveal(){revealTarget=null;}
  center.addEventListener('compositionend',finishComposition);for(const event of ['pointerdown','input','keydown'])center.addEventListener(event,clearReveal);
  function beatCards(){const d=api.document(),segments=model.scriptSegments(d),numbers=new Map(segments.map(segment=>[segment.scene.id,segment.number]));return model.board(d).beats.filter(beat=>numbers.has(beat.sceneID)&&!beat.omitted).sort((a,b)=>a.order-b.order).map(beat=>({beat,scene:model.scene(d,beat.sceneID),number:numbers.get(beat.sceneID)}));}
  function conversionReview(){
    const source=structuredClone(api.document()),dialog=el('dialog',null,'conversion-review'),choices={};
    dialog.append(el('h2','Review Converted Copy'),el('p','The original project stays unchanged. Choose which scenes receive shared data. Multiple selections explicitly copy it. Original history and unknown fields remain available as legacy reference.'));
    for(const group of conversionGroups(source)){
      const section=el('section');section.append(el('h3',group.scene.title));if(group.conflict)section.append(el('p','Title or summary differs: each resulting scene will use its whiteboard beat title and synopsis. The originals remain in legacy reference.','warning'));
      for(const beat of group.beats)section.append(el('p',beat.title+' — '+(beat.synopsis||'No summary')));
      choices[group.scene.id]={};
      for(const category of ['notes','breakdown','attachments','production']){
        choices[group.scene.id][category]=group.beats[0]?[group.beats[0].id]:[];
        const field=el('fieldset');field.append(el('legend',model.label(category)));
        for(const beat of group.beats){const label=el('label'),check=el('input');check.type='checkbox';check.checked=beat===group.beats[0];check.onchange=()=>{const list=choices[group.scene.id][category];choices[group.scene.id][category]=check.checked?[...list,beat.id]:list.filter(id=>id!==beat.id);};label.append(check,document.createTextNode(beat.title));field.append(label);}section.append(field);
      }dialog.append(section);
    }
    dialog.append(button('Create Converted Copy',async()=>{const next=convertSceneCopy(source,choices);await api.createConvertedCopy(next);dialog.close();dialog.remove();},true),button('Cancel',()=>{dialog.close();dialog.remove();}));document.body.append(dialog);dialog.showModal();dialog.addEventListener('cancel',()=>dialog.remove());
  }
  function editCardText(node,beat,key){
    if(api.readonly()||beat.locked||blockLocked(model.board(api.document()),beat.blockID)||model.scene(api.document(),beat.sceneID).frontstageTextLocked)return;
    const input=el(key==='title'?'input':'textarea');input.value=beat[key]||'';input.setAttribute('aria-label',key==='title'?'Beat title':'Beat summary');let done=false,composing=false;
    const finish=save=>{if(done||composing)return;done=true;if(save)api.change(d=>updateBeatCard(d,beat.id,{[key]:input.value}));renderLeft();};
    input.oncompositionstart=()=>composing=true;input.oncompositionend=()=>{composing=false;if(document.activeElement!==input)finish(true);};input.onblur=()=>finish(true);
    input.onkeydown=e=>{if(e.isComposing)return;if(e.key==='Escape'){e.preventDefault();finish(false);}else if(e.key==='Enter'&&(key==='title'||e.ctrlKey||e.metaKey)){e.preventDefault();finish(true);}};
    input.onclick=e=>e.stopPropagation();node.replaceWith(input);input.focus();input.select();
  }
  function cardView(card){
    const {beat,scene,number}=card,box=el('article',null,'scene-summary-card simple-beat-card');box.dataset.sceneId=scene.id;box.dataset.beatId=beat.id;box.tabIndex=0;box.classList.toggle('selected',beat.id===current.beatID);
    const header=el('div',null,'beat-card-header'),badge=el('span',number+' ·','scene-number-badge'),title=el('strong',beat.title||'Untitled Beat');title.dataset.cardField='title';badge.dataset.cardField='number';header.append(badge,title);box.append(header);
    const summary=el('div',beat.synopsis||'Double-click to add a summary…','beat-card-synopsis');summary.dataset.cardField='synopsis';summary.classList.toggle('empty',!beat.synopsis);box.append(summary);
    if((beat.synopsis||'').length>220)box.append(button('Show more',()=>summary.classList.toggle('expanded')));
    title.ondblclick=e=>{e.stopPropagation();editCardText(title,beat,'title');};summary.ondblclick=e=>{e.stopPropagation();editCardText(summary,beat,'synopsis');};
    box.onclick=e=>{if(e.target.closest('input,textarea,button'))return;navigate({scene,beats:[beat]},beat.id);};box.onkeydown=e=>{if(e.target!==box)return;if(e.key==='Enter')navigate({scene,beats:[beat]},beat.id);if(e.key==='F2'){e.preventDefault();editCardText(title,beat,'title');}};
    box.oncontextmenu=e=>{e.preventDefault();document.querySelector('.write-card-menu')?.remove();const menu=el('div',null,'write-card-menu');menu.setAttribute('role','menu');menu.style.left=e.clientX+'px';menu.style.top=e.clientY+'px';for(const [label,action]of [['Edit title',()=>editCardText(title,beat,'title')],['Edit summary',()=>editCardText(summary,beat,'synopsis')],['Duplicate Beat',()=>{api.change(d=>duplicateBeat(d,beat.id));api.rebuild();}],['Pull Out Scene',()=>{api.change(d=>replaceDocument(d,pullOutBeats(d,new Set([beat.id]))));api.rebuild();}]]){const item=button(label,()=>{menu.remove();action();},true);item.setAttribute('role','menuitem');menu.append(item);}document.body.append(menu);setTimeout(()=>document.addEventListener('click',()=>menu.remove(),{once:true}),0);};
    box.draggable=!api.readonly();box.ondragstart=e=>{if(e.target.closest('input,textarea')){e.preventDefault();return;}e.dataTransfer.setData('text/frontstage-card',beat.id);};
    box.ondragover=e=>{if(![...e.dataTransfer.types].includes('text/frontstage-card'))return;e.preventDefault();box.dataset.drop=e.clientY<box.getBoundingClientRect().top+box.clientHeight/2?'before':'after';};box.ondragleave=()=>delete box.dataset.drop;
    box.ondrop=e=>{e.preventDefault();const source=e.dataTransfer.getData('text/frontstage-card'),after=box.dataset.drop==='after';delete box.dataset.drop;if(!source||source===beat.id)return;const ordered=[...model.board(api.document()).beats].sort((a,b)=>a.order-b.order).filter(b=>b.id!==source),index=ordered.findIndex(b=>b.id===beat.id),target=after?ordered[index+1]?.id??null:beat.id;run(()=>{api.change(d=>{const board=model.board(d);for(const b of board.beats)if((b.id===source||b.id===target)&&model.scene(d,b.sceneID).frontstageTextLocked)throw Error('Unlock the scene before reordering.');d.project.frontstageWhiteboard=reorderTimelineBeats(board,new Set([source]),target);});api.rebuild();});};return box;
  }
  function refreshMetadata(){const label=rightBody.querySelector('[data-note-target]');if(label)label.textContent='Scene notes · '+(model.board(api.document()).beats.find(b=>b.id===current.beatID)?.title||scene()?.title||'Select a scene');for(const card of beatCards()){const box=[...leftBody.querySelectorAll('.simple-beat-card')].find(node=>node.dataset.beatId===card.beat.id);if(!box)continue;box.classList.toggle('selected',card.beat.id===current.beatID);for(const [field,value]of Object.entries({title:card.beat.title,number:card.number+' ·',synopsis:card.beat.synopsis||'Double-click to add a summary…'})){const node=box.querySelector('[data-card-field="'+field+'"]');if(node)node.textContent=value;}}}
  function renderLeft(){leftBody.replaceChildren();tabs(leftBody,['Scenes','Locations'],'leftTab');const filter=el('input');filter.type='search';filter.placeholder='Search scenes';filter.setAttribute('aria-label','Search scenes');filter.value=search;filter.oninput=()=>{search=filter.value;renderCards();};leftBody.append(filter);if(!isSceneModel(api.document()))leftBody.append(button('Review Converted Copy',conversionReview,true));const list=el('div');leftBody.append(list);
    function renderCards(){list.replaceChildren();const cards=beatCards().filter(c=>[c.number,model.heading(c.scene),c.beat.title,c.beat.synopsis].join(' ').toLocaleLowerCase().includes(search.toLocaleLowerCase()));if(pref.leftTab==='Locations'){const groups=new Map();for(const card of cards){const key=(card.scene.slug?.location||'Unspecified').trim().toLocaleUpperCase();if(!groups.has(key))groups.set(key,[]);groups.get(key).push(card);}for(const[key,cards]of groups){const group=el('details');group.append(el('summary',`${key} (${cards.length})`));for(const c of cards)group.append(cardView(c));list.append(group);}}else for(const c of cards)list.append(cardView(c));}renderCards();
  }
  function renderNotes(s){rightBody.dataset.combinedNotes=String(pref.scope==='Both');rightBody.append(select('Note scope',pref.scope,['Scene','Project','Both'],value=>{pref.scope=value;save();renderRight();}));if((pref.scope==='Scene'||pref.scope==='Both')&&s)renderNoteScope(s,s.id);if(pref.scope==='Project'||pref.scope==='Both')renderNoteScope(s,null);}
  function noteColorPicker(note,id){const field=el('label','Note color'),choice=el('select'),palette=[['#fff4bc','Yellow'],['#d9edff','Blue'],['#e1f4dc','Green'],['#f8dce7','Pink'],['#ffffff','White']];choice.setAttribute('aria-label','Note color');choice.disabled=api.readonly()||(id!=null&&model.scene(api.document(),id).frontstageTextLocked);const swatches=el('nav',null,'note-color-swatches');for(const[color,name]of palette){choice.append(new Option(name,color));const b=button(name,()=>mutate(d=>data.updateNote(d,id,note.id,{color})),true);b.disabled=choice.disabled;b.style.setProperty('--swatch',color);b.setAttribute('aria-label','Set note color to '+name);b.setAttribute('aria-pressed',String(note.color===color));swatches.append(b);}if(note.color&&!palette.some(([c])=>c===note.color))choice.append(new Option('Custom',note.color));choice.value=note.color||'#fff4bc';choice.onchange=()=>mutate(d=>data.updateNote(d,id,note.id,{color:choice.value}));field.append(choice,swatches);return field;}
  function renderNoteScope(s,id){const scopeBody=el('section');scopeBody.dataset.noteScope=id==null?'Project':'Scene';scopeBody.setAttribute('aria-label',id==null?'Project notes':'Scene notes');rightBody.append(scopeBody);const owner=id==null?api.document().project:s;
    const target=el('h3',id==null?'Project notes':`Scene notes · ${model.board(api.document()).beats.find(b=>b.id===current.beatID)?.title||s.title}`);if(id!=null)target.dataset.noteTarget=String(id);scopeBody.append(target,button('Add Note',()=>mutate(d=>data.addNote(d,id)),true));
    if(owner.scratchpad){const legacy=el('details');legacy.append(el('summary','Legacy scratchpad (preserved)'),el('pre',String(owner.scratchpad)));scopeBody.append(legacy);}
    if(owner[id==null?'globalNotes':'notes']!=null&&!Array.isArray(owner[id==null?'globalNotes':'notes']))scopeBody.append(el('p','Unsupported imported notes are preserved.'));
    for(const note of (Array.isArray(owner[id==null?'globalNotes':'notes'])?owner[id==null?'globalNotes':'notes']:[])){
      const card=el('article',null,'writing-note');card.style.background=/^#[0-9a-f]{6}$/i.test(note.color||'')?note.color:'#fff4bc';const supported=data.editableNote(note);
      card.dataset.noteId=String(note.id);const editor=el('div',null,'note-content');editor.contentEditable=supported&&!api.readonly()&&!(id!=null&&s?.frontstageTextLocked);editor.setAttribute('role','textbox');editor.setAttribute('aria-label','Note text');editor.innerHTML=data.safeNoteHTML(note.content);
      if(supported){const format=el('nav');for(const command of ['bold','italic','strikeThrough','insertUnorderedList','insertOrderedList']){const b=button(command,()=>{editor.focus();document.execCommand(command);editor.dispatchEvent(new Event('input'));},true);b.onmousedown=e=>e.preventDefault();format.append(b);}card.append(format);const commit=()=>{if(editor.isComposing)return;run(()=>mutate(d=>data.updateNote(d,id,note.id,{content:data.safeNoteHTML(editor.innerHTML)}),false));};attachLiveMarkdown(editor,commit);editor.oninput=commit;editor.addEventListener('compositionstart',()=>editor.isComposing=true);editor.addEventListener('compositionend',()=>{editor.isComposing=false;commit();});card.append(editor,noteColorPicker(note,id),button('Move Note Up',()=>mutate(d=>data.moveNote(d,id,note.id,-1)),true),button('Move Note Down',()=>mutate(d=>data.moveNote(d,id,note.id,1)),true),button('Delete Note',()=>mutate(d=>data.removeNote(d,id,note.id)),true));}else card.append(editor,el('p','Unsupported imported note · preserved read-only'));scopeBody.append(card);
    }
  }
  function renderBreakdown(s){if(!s)return;const id=s.id;rightBody.append(el('h3',`Breakdown · ${s.title}`));const searchBox=el('input');searchBox.placeholder='Search breakdown';searchBox.value=breakdownSearch;searchBox.oninput=()=>{breakdownSearch=searchBox.value;renderItems();};rightBody.append(searchBox);
    let category='PROPS',name='',quantity=1,description='';rightBody.append(select('New item category',category,model.categories,v=>category=v),input('Item name','',v=>name=v),input('Quantity',1,v=>quantity=Number(v)),input('Description','',v=>description=v,true),button('Add Requirement',()=>mutate(d=>{data.writableScene(d,id);model.addRequirement(d,id,category,name,quantity,description);}),true));
    const fromSelection=button('Add Selected Script Text',()=>{if(!quote||quoteScene!==id)throw Error('Select screenplay text in this scene first.');mutate(d=>{data.writableScene(d,id);model.addRequirement(d,id,category,quote,1,'');const entry=model.breakdownEntries(model.scene(d,id)).filter(e=>e.bucket===category).at(-1);model.scene(d,id)[entry.storage][entry.bucket][entry.index].sourceQuote=quote;});},true);rightBody.append(fromSelection);const list=el('div');rightBody.append(list);
    function renderItems(){list.replaceChildren();const entries=model.breakdownEntries(s),groups=[...model.categories,...new Set(entries.map(data.normalizedCategory).filter(c=>!model.categories.includes(c)))];for(const category of groups){const values=entries.filter(e=>data.normalizedCategory(e)===category),group=el('details');group.append(el('summary',`${model.categories.includes(category)?model.label(category):'Imported · '+category} (${values.length})`));for(const entry of values.filter(e=>[e.name,e.description].join(' ').toLowerCase().includes(breakdownSearch.toLowerCase()))){const item=el('article',null,'workspace-card');if(entry.id)item.dataset.requirementId=entry.id;if(entry.frontstageSourceLinked){const sources=[...model.board(api.document()).beats.filter(b=>b.sceneID===id).map(b=>b.html||''),s.frontstageHeadingMarkup||''];if(!sources.some(html=>annotationIDs(html).includes(entry.id)))item.append(el('small','Source text is no longer present. The breakdown item is retained.'));}const update=(key,value)=>mutate(d=>{const s=data.writableScene(d,id),list=s[entry.storage][entry.bucket],old=list[entry.index];if(entry.id&&old.id!==entry.id)throw Error('Item changed; select it again.');list[entry.index]=typeof old==='string'?{name:old}:old;list[entry.index][key]=value;},false);item.append(input('Requirement name',entry.name,v=>{if(!v.trim())throw Error('Enter a name.');update('name',v);}),input('Requirement quantity',entry.count||1,v=>{if(!Number.isInteger(+v)||+v<1||+v>100000)throw Error('Enter a positive quantity.');update('count',+v);}),input('Requirement description',entry.description,v=>update('description',v),true),select('Move to category',category,[...new Set([category,...model.categories])],v=>mutate(d=>data.moveRequirement(d,id,entry,v))),button('Delete Requirement',()=>mutate(d=>{data.writableScene(d,id)[entry.storage][entry.bucket].splice(entry.index,1);}),true));if(entry.sourceQuote)item.append(el('blockquote',entry.sourceQuote));group.append(item);}list.append(group);}}renderItems();
  }
  function comparison(before,after){const result=el('div',null,'revision-diff'),old=api.plain(before||'').split('\n'),now=api.plain(after||'').split('\n');for(let i=0;i<Math.max(old.length,now.length);i++){if(old[i]===now[i])result.append(el('div','  '+old[i]));else{if(i<old.length)result.append(el('div','− '+old[i],'removed'));if(i<now.length)result.append(el('div','+ '+now[i],'added'));}}return result;}
  function renderHistory(s){if(!s)return;const id=s.id;const legacy=api.document().project.frontstageLegacyScenes?.beats?.find(scene=>scene.id===s.frontstageLegacySceneID);if(legacy){const reference=el('details');reference.append(el('summary','Original scene · legacy reference (read-only)'),el('p',legacy.title),el('p',legacy.summary||''));for(const version of legacy.versions||[]){const entry=el('details');entry.append(el('summary',version.frontstageLabel||version.title||'Legacy snapshot'),el('pre',api.plain(version.content||'')));reference.append(entry);}rightBody.append(reference);}let label='';rightBody.append(el('h3',`History · ${s.title}`),input('Snapshot label','',v=>label=v),button('Capture Snapshot',()=>mutate(d=>model.captureRevision(d,id,label)),true));for(const revision of [...(s.versions||[])].sort((a,b)=>(b.timestamp||0)-(a.timestamp||0))){const entry=el('details');entry.append(el('summary',revision.frontstageLabel||revision.title||'Snapshot'),el('small',new Date(revision.timestamp||0).toLocaleString()),el('p',revision.summary||''),el('h4','Saved screenplay'),el('pre',api.plain(revision.content||'')),el('h4','Current screenplay'),el('pre',api.plain(s.content||'')),el('h4','Comparison · − saved / + current'),comparison(revision.content,s.content),button('Restore This Snapshot',()=>{if(!confirm('Restore this scene? A backup of the current version will be saved. Notes and breakdown stay unchanged.'))return;api.change(d=>model.restoreRevision(d,id,revision.id));api.rebuild();},true));if(!revision.frontstageSnippets&&model.board(api.document()).beats.filter(b=>b.sceneID===id).length>1){entry.append(el('p','This legacy snapshot has no beat boundaries. Restoring a multi-beat scene is unsafe.'));entry.querySelector('button').disabled=true;}rightBody.append(entry);}}
  function renderRight(){rightBody.replaceChildren();delete rightBody.dataset.combinedNotes;tabs(rightBody,['Notes','Breakdown','History'],'rightTab');const s=scene();if(pref.rightTab==='Notes')renderNotes(s);if(pref.rightTab==='Breakdown')renderBreakdown(s);if(pref.rightTab==='History')renderHistory(s);}
  function refreshPanels(){renderLeft();renderRight();}
  function captureSelection(){const selection=window.getSelection(),node=selection?.anchorNode?.parentElement,script=node?.closest('[data-beat-id]');if(script&&selection.toString()){quote=selection.toString();quoteScene=model.board(api.document()).beats.find(b=>b.id===script.dataset.beatId)?.sceneID;}}
  center.addEventListener('mouseup',captureSelection);center.addEventListener('keyup',captureSelection);
  
  function drawerKeys(event){
    if(!drawer||event.isComposing||document.activeElement?.isComposing)return;
    if(event.key==='Escape'&&!document.querySelector('.autofill-list')){event.preventDefault();event.stopPropagation();closeDrawer();return;}
    if(event.key!=='Tab')return;
    const panel=drawer==='left'?left:right,focusable=[...panel.querySelectorAll('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href],[contenteditable=true],[tabindex]:not([tabindex="-1"])')].filter(node=>node.getClientRects().length),first=focusable[0],last=focusable.at(-1);
    if(event.shiftKey&&(document.activeElement===first||!panel.contains(document.activeElement))){event.preventDefault();last?.focus();}else if(!event.shiftKey&&(document.activeElement===last||!panel.contains(document.activeElement))){event.preventDefault();first?.focus();}
  }
  const resize=new ResizeObserver(widths);resize.observe(host);
  window.addEventListener('resize',widths);window.visualViewport?.addEventListener('resize',widths);window.visualViewport?.addEventListener('scroll',widths);document.addEventListener('keydown',drawerKeys,true);
  widths();refreshPanels();
  return {showBreakdown(sceneID,beatID,requirementID){current={sceneID,beatID};pref.rightTab='Breakdown';pref.rightOpen=true;save();renderRight();if(isOverlay('right')&&drawer!=='right')toggle('right');else widths();requestAnimationFrame(()=>{const item=[...rightBody.querySelectorAll('[data-requirement-id]')].find(n=>n.dataset.requirementId===requirementID);if(item){item.closest('details').open=true;item.scrollIntoView({block:'nearest'});}});},toggleLeft:()=>toggle('left'),reveal(sceneID,beatID){const scene=model.scene(api.document(),sceneID);navigate({scene,beats:[{id:beatID}]},beatID);},refreshMetadata,destroy(){cancelAnimationFrame(revealFrame);center.removeEventListener('compositionend',finishComposition);for(const event of ['pointerdown','input','keydown'])center.removeEventListener(event,clearReveal);resize.disconnect();window.removeEventListener('resize',widths);window.visualViewport?.removeEventListener('resize',widths);window.visualViewport?.removeEventListener('scroll',widths);document.removeEventListener('keydown',drawerKeys,true);center.inert=false;for(const[name,value]of[['aria-controls',oldControls],['aria-expanded',oldExpanded]]){if(value==null)scenesToggle?.removeAttribute(name);else scenesToggle?.setAttribute(name,value);}},select(sceneID,beatID){if(current.sceneID===sceneID&&current.beatID===beatID)return;current={sceneID,beatID};refreshMetadata();renderRight();},refresh:refreshPanels};
}
