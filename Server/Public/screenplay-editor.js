export const elements = ['action','character','dialogue','parenthetical','transition','shot','lyrics'];
export function screenplayToolbar(text, changed, editable=true, characters=()=>[]) {
  const bar=document.createElement('div');bar.className='screenplay-toolbar';
  const select=document.createElement('select');select.setAttribute('aria-label','Element');
  for(const key of elements){const o=document.createElement('option');o.value=key;o.textContent=key[0].toUpperCase()+key.slice(1);select.append(o);}
  const paragraph=()=>{let node=window.getSelection()?.anchorNode;if(node?.nodeType===3)node=node.parentElement;if(!node||!text.contains(node))return null;while(node!==text&&node.parentElement!==text)node=node.parentElement;return node;};
  const format=kind=>{if(!text.isContentEditable)return;text.focus();let node=paragraph();if(node===text){document.execCommand('formatBlock',false,'p');node=paragraph();}if(node&&node!==text){node.className=`sc-line sc-${kind}`;capitalizeCue(node);select.value=kind;changed();}};
  select.onchange=()=>format(select.value);select.disabled=!editable;bar.append(select);
  for(const command of ['bold','italic','underline']){const b=document.createElement('button');b.textContent=command==='bold'?'B':command==='italic'?'I':'U';b.setAttribute('aria-label',command);b.disabled=!editable;b.onpointerdown=e=>e.preventDefault();b.onclick=()=>{text.focus();document.execCommand(command);changed();};bar.append(b);}
  let savedRange;
  const remember=()=>{const selection=window.getSelection();if(selection?.rangeCount && text.contains(selection.anchorNode))savedRange=selection.getRangeAt(0).cloneRange();};
  for(const event of ['keyup','mouseup','blur'])text.addEventListener(event,remember);
  const insertCue=(value,kind)=>{
    if(!text.isContentEditable)return;text.focus();
    if(savedRange && text.contains(savedRange.startContainer)){const selection=window.getSelection();selection.removeAllRanges();selection.addRange(savedRange);}
    let node=paragraph();
    if(node===text){document.execCommand('formatBlock',false,'p');node=paragraph();}
    const selection=window.getSelection(),range=document.createRange();
    if(node && node!==text && (!node.textContent.trim() || node.classList.contains('sc-'+kind))){range.selectNodeContents(node);selection.removeAllRanges();selection.addRange(range);document.execCommand('insertText',false,value);format(kind);}
    else {
      if(node && node!==text)range.selectNodeContents(node);else range.selectNodeContents(text);
      range.collapse(false);selection.removeAllRanges();selection.addRange(range);
      document.execCommand('insertParagraph');format(kind);document.execCommand('insertText',false,value);changed();
    }
    remember();
  };
  for(const [label,kind,values] of [['Character','character',characters],['Transition','transition',()=>['CUT TO:','DISSOLVE TO:','FADE IN:','FADE OUT.','FADE TO BLACK.','SMASH CUT TO:','MATCH CUT TO:']],['Parenthetical','parenthetical',()=>['(beat)','(quietly)','(into phone)']],['Shot','shot',()=>['CLOSE ON','ANGLE ON','INSERT','POV']]]){
    const menu=document.createElement('select');menu.setAttribute('aria-label',label);menu.disabled=!editable;
    const populate=()=>{menu.replaceChildren(new Option(label,''));for(const value of [...new Set(values())].filter(Boolean).sort())menu.append(new Option(value,value));};
    populate();menu.onpointerdown=()=>{remember();populate();};menu.onchange=()=>{if(menu.value)insertCue(menu.value,kind);menu.value='';};bar.append(menu);
  }
  text.addEventListener('keyup',()=>{const node=paragraph();if(node)select.value=elements.find(e=>node.classList.contains('sc-'+e))||'action';});
  text.addEventListener('keydown',event=>{
    if(event.isComposing||!text.isContentEditable)return;
    if(event.key==='Tab'){event.preventDefault();const node=paragraph(),kind=elements.find(e=>node?.classList.contains('sc-'+e))||'action',empty=!node?.textContent.trim();if(event.shiftKey){format(elements[(elements.indexOf(kind)+elements.length-1)%elements.length]);return;}if(kind==='character')return;const next=kind==='dialogue'?'parenthetical':kind==='parenthetical'?'dialogue':'character';if(!empty||kind==='action')document.execCommand('insertParagraph');format(next);}
    if((event.altKey||event.ctrlKey||event.metaKey)&&/^[1-7]$/.test(event.key)){event.preventDefault();format(elements[Number(event.key)-1]);}
    if(event.key==='Enter'&&!event.shiftKey){const node=paragraph(),kind=elements.find(e=>node?.classList.contains('sc-'+e))||'action',empty=!node?.textContent.trim(),next=kind==='character'||kind==='parenthetical'?'dialogue':kind==='lyrics'?'lyrics':'action';event.preventDefault();if(!empty||['action','character','dialogue'].includes(kind))document.execCommand('insertParagraph');format(next);}
  });
  text.addEventListener('input',event=>{if(!event.isComposing)capitalizeCue(paragraph());},true);
  text.addEventListener('compositionend',()=>{if(capitalizeCue(paragraph()))changed();});
  text.addEventListener('blur',()=>{let updated=false;for(const line of text.querySelectorAll('.sc-character,.sc-slugline,.sc-transition'))updated=capitalizeCue(line)||updated;if(updated)changed();});
  attachCompletions(text,paragraph,characters,changed);
  let caretFrame;
  const followCaret=()=>{cancelAnimationFrame(caretFrame);caretFrame=requestAnimationFrame(()=>{
    const selection=window.getSelection();if(!text.isConnected||!selection?.rangeCount||!text.contains(selection.focusNode)||!selection.isCollapsed)return;
    const range=selection.getRangeAt(0);let rect=range.getBoundingClientRect();
    if(!rect.height)rect=paragraph()?.getBoundingClientRect();if(!rect)return;
    for(let pane=text;pane&&pane!==document.body;pane=pane.parentElement){
      if(!/(auto|scroll)/.test(getComputedStyle(pane).overflowY)||pane.scrollHeight<=pane.clientHeight)continue;
      const bounds=pane.getBoundingClientRect(),delta=rect.bottom>bounds.bottom-20?rect.bottom-bounds.bottom+20:rect.top<bounds.top+12?rect.top-bounds.top-12:0;
      if(delta){pane.scrollTop+=delta;rect=range.getBoundingClientRect();}
    }
  });};
  for(const event of ['input','keyup','click','compositionend'])text.addEventListener(event,followCaret);
  bar.editor={format:kind=>{text.focus();if(savedRange&&text.contains(savedRange.startContainer)){const selection=window.getSelection();selection.removeAllRanges();selection.addRange(savedRange);}format(kind);},inline:command=>{text.focus();if(savedRange&&text.contains(savedRange.startContainer)){const selection=window.getSelection();selection.removeAllRanges();selection.addRange(savedRange);}document.execCommand(command);changed();},remember};
  return bar;
}
export function splitAtCaret(text) {
  const selection=window.getSelection();if(!selection?.rangeCount)throw Error('Place the cursor inside the snippet before splitting.');
  const cursor=selection.getRangeAt(0);if(!cursor.collapsed||!text.contains(cursor.startContainer))throw Error('Place the cursor inside the snippet before splitting.');
  const first=document.createRange();first.selectNodeContents(text);first.setEnd(cursor.startContainer,cursor.startOffset);
  const last=document.createRange();last.selectNodeContents(text);last.setStart(cursor.startContainer,cursor.startOffset);
  const a=document.createElement('div'),b=document.createElement('div');a.append(first.cloneContents());b.append(last.cloneContents());
  if(!a.textContent.length||!b.textContent.length)throw Error('Place the cursor inside the snippet before splitting.');return[a.innerHTML,b.innerHTML];
}

export function characterNames(document) {
  const project=document.project,beats=project.frontstageWhiteboard?.beats||[];
  const cues=[...beats.map(b=>b.html||''),...(project.beats||[]).map(s=>s.content||'')].flatMap(html=>[...new DOMParser().parseFromString(html,'text/html').querySelectorAll('.sc-character')].map(n=>n.textContent.replace(/\s*\((?:V\.O\.|O\.S\.|CONT['’]D)\)\s*$/i,'')));
  return [...new Set([...Object.entries(project.characterData||{}).map(([key,value])=>value.name||key),...beats.flatMap(b=>b.characters||[]),...cues].map(n=>n.trim().normalize('NFC').toUpperCase()).filter(Boolean))].sort();
}
// Each control resolves its scene on every edit so simultaneous popups cannot overwrite another scene.
export function sluglineFields(getScene, getScenes, commit, editable=true) {
  const root=document.createElement('div');root.className='slugline-fields';root.setAttribute('aria-label','Slugline');
  const caption=document.createElement('strong');caption.textContent='SLUGLINE';root.append(caption);
  for(const [key,label,fallback,options] of [['prefix','INT. / EXT.','INT.',['INT.','EXT.','INT./EXT.','EXT./INT.']],['location','Location','',getScenes().map(s=>s.slug?.location).filter(Boolean)],['time','DAY / NIGHT','DAY',['DAY','NIGHT','DAWN','DUSK','MORNING','AFTERNOON','EVENING','LATER','CONTINUOUS','SAME TIME']]]) {
    const wrap=document.createElement('label');wrap.textContent=label;
    const input=document.createElement('input');input.setAttribute('aria-label',label);input.dataset.slugKey=key;input.value=getScene()?.slug?.[key]??fallback;input.disabled=!editable||!!getScene()?.frontstageTextLocked;
    inputCompletions(input,()=>key==='location'?getScenes().map(s=>s.slug?.location).filter(Boolean):options);
    const save=()=>{const value=input.value.trim().toUpperCase();input.value=value;if(getScene()?.slug?.[key]===value)return;commit(()=>{const scene=getScene();if(!scene||scene.frontstageTextLocked)throw Error('Unlock the scene heading before changing it.');(scene.slug||={})[key]=value;});};
    input.onchange=save;input.addEventListener('blur',save);
    const combo=document.createElement('div');combo.className='slugline-combo';combo.append(input);wrap.append(combo);root.append(wrap);
  }
  root.refresh=()=>{const scene=getScene();for(const choice of root.querySelectorAll('[data-slug-options]'))choice.disabled=!editable||!!scene?.frontstageTextLocked;for(const input of root.querySelectorAll('[data-slug-key]')){input.disabled=!editable||!!scene?.frontstageTextLocked;if(document.activeElement!==input)input.value=scene?.slug?.[input.dataset.slugKey]??(input.dataset.slugKey==='prefix'?'INT.':input.dataset.slugKey==='time'?'DAY':'');}};
  return root;
}

function attachCompletions(text,paragraph,characters,changed) {
  let popup=null,values=[],index=0,line=null;
  const close=()=>{popup?.remove();popup=null;values=[];};
  const choose=(advance=false)=>{if(!line||!values[index])return;const value=values[index];close();text.focus();const range=document.createRange();range.selectNodeContents(line);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);document.execCommand('insertText',false,value);if(advance&&line.classList.contains('sc-character')){document.execCommand('insertParagraph');let next=window.getSelection()?.anchorNode;if(next?.nodeType===3)next=next.parentElement;while(next&&next.parentElement!==text)next=next.parentElement;if(next)next.className='sc-line sc-dialogue';}changed();};
  const highlight=()=>popup?.querySelectorAll('button').forEach((b,i)=>b.setAttribute('aria-selected',String(i===index)));
  text.addEventListener('input',event=>{
    close();if(event.isComposing||!text.isContentEditable)return;
    line=paragraph();if(!line||line===text)return;const prefix=line.textContent;
    const kind=elements.find(k=>line.classList.contains('sc-'+k));
    const choices={character:characters(),transition:['CUT TO:','DISSOLVE TO:','FADE IN:','FADE OUT.','FADE TO BLACK.','SMASH CUT TO:','MATCH CUT TO:'],parenthetical:['(beat)','(quietly)','(into phone)'],shot:['CLOSE ON','ANGLE ON','INSERT','POV']}[kind]||[];
    if(!prefix.trim())return;values=[...new Set(choices)].filter(v=>v.toLowerCase().startsWith(prefix.toLowerCase())&&v.toLowerCase()!==prefix.toLowerCase()).slice(0,12);if(!values.length)return;
    popup=document.createElement('div');popup.className='autofill-list';popup.setAttribute('role','listbox');popup.setAttribute('aria-label','Screenplay suggestions');index=0;
    for(const [i,value]of values.entries()){const button=document.createElement('button');button.textContent=value;button.setAttribute('role','option');button.onpointerdown=e=>{e.preventDefault();index=i;choose();};popup.append(button);}
    const rect=window.getSelection()?.getRangeAt(0).getBoundingClientRect()||line.getBoundingClientRect();popup.style.left=Math.min(rect.left,window.innerWidth-220)+'px';popup.style.top=Math.min(rect.bottom+4,window.innerHeight-190)+'px';document.body.append(popup);highlight();
  });
  text.addEventListener('keydown',event=>{if(!popup||event.isComposing)return;if(['ArrowDown','ArrowUp','Enter','Tab','Escape'].includes(event.key)){event.preventDefault();event.stopImmediatePropagation();if(event.key==='Escape')close();else if(['Enter','Tab'].includes(event.key))choose(event.key==='Enter');else{index=(index+(event.key==='ArrowDown'?1:values.length-1))%values.length;highlight();}}},true);
  text.addEventListener('blur',close);text.addEventListener('compositionstart',close);
}

// Keep text and caret positions intact while normalizing screenplay cues.
export function capitalizeCue(line) {
  if(!line?.matches('.sc-character,.sc-slugline,.sc-transition'))return false;
  const selection=window.getSelection(),anchor=selection?.anchorNode,focus=selection?.focusNode;
  let a=selection?.anchorOffset||0,f=selection?.focusOffset||0,changed=false;
  const walker=document.createTreeWalker(line,NodeFilter.SHOW_TEXT);let node;
  while((node=walker.nextNode())){const original=node.data,upper=original.toUpperCase();if(original===upper)continue;if(node===anchor)a=original.slice(0,a).toUpperCase().length;if(node===focus)f=original.slice(0,f).toUpperCase().length;node.data=upper;changed=true;}
  if(changed&&anchor&&focus&&line.contains(anchor)&&line.contains(focus))selection.setBaseAndExtent(anchor,a,focus,f);
  return changed;
}
function inputCompletions(input,options){
  let popup,index=0,values=[];
  const close=()=>{popup?.remove();popup=null;input.setAttribute('aria-expanded','false');};
  const choose=()=>{input.value=values[index];close();input.dispatchEvent(new Event('change'));};
  input.setAttribute('role','combobox');input.setAttribute('aria-autocomplete','list');input.setAttribute('aria-expanded','false');
  const show=event=>{close();if(event?.isComposing||input.disabled)return;values=[...new Set(options().filter(Boolean).map(v=>v.trim().toUpperCase()))].filter(v=>v.startsWith(input.value.trim().toUpperCase())&&v!==input.value.toUpperCase()).slice(0,12);if(!values.length)return;
    popup=document.createElement('div');popup.className='autofill-list';popup.setAttribute('role','listbox');popup.setAttribute('aria-label','Slugline suggestions');index=0;
    for(const [i,value]of values.entries()){const b=document.createElement('button');b.textContent=value;b.setAttribute('role','option');b.setAttribute('aria-selected',String(i===0));b.onpointerdown=e=>{e.preventDefault();index=i;choose();};popup.append(b);}
    const r=input.getBoundingClientRect();popup.style.left=Math.max(0,Math.min(r.left,innerWidth-220))+'px';popup.style.top=Math.max(0,Math.min(r.bottom+4,innerHeight-190))+'px';document.body.append(popup);input.setAttribute('aria-expanded','true');};
  input.addEventListener('input',show);input.addEventListener('focus',show);input.addEventListener('compositionend',show);input.addEventListener('compositionstart',close);input.addEventListener('blur',close);
  input.addEventListener('keydown',event=>{if(!popup||event.isComposing)return;if(['ArrowDown','ArrowUp','Enter','Tab','Escape'].includes(event.key)){event.preventDefault();event.stopPropagation();if(event.key==='Escape')close();else if(['Enter','Tab'].includes(event.key))choose();else{index=(index+(event.key==='ArrowDown'?1:values.length-1))%values.length;popup.querySelectorAll('button').forEach((b,i)=>b.setAttribute('aria-selected',String(i===index)));}}});
}
