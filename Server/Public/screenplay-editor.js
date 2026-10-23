export const elements = ['action','character','dialogue','parenthetical','transition','shot','lyrics'];
export function screenplayToolbar(text, changed, editable=true, characters=()=>[]) {
  const bar=document.createElement('div');bar.className='screenplay-toolbar';
  const select=document.createElement('select');select.setAttribute('aria-label','Element');
  for(const key of elements){const o=document.createElement('option');o.value=key;o.textContent=key[0].toUpperCase()+key.slice(1);select.append(o);}
  const paragraph=()=>{let node=window.getSelection()?.anchorNode;if(node?.nodeType===3)node=node.parentElement;if(!node||!text.contains(node))return null;while(node!==text&&node.parentElement!==text)node=node.parentElement;return node;};
  const format=kind=>{if(!text.isContentEditable)return;text.focus();let node=paragraph();if(node===text){document.execCommand('formatBlock',false,'p');node=paragraph();}if(node&&node!==text){node.className=`sc-line sc-${kind}`;select.value=kind;changed();}};
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
    if(event.key==='Tab'){event.preventDefault();format(elements[(elements.indexOf(select.value)+(event.shiftKey?6:1))%7]);}
    if(event.altKey&&/^[1-7]$/.test(event.key)){event.preventDefault();format(elements[Number(event.key)-1]);}
    if(event.key==='Enter'&&!event.shiftKey){const node=paragraph(),kind=elements.find(e=>node?.classList.contains('sc-'+e))||'action',empty=!node?.textContent.trim(),next=empty?'action':kind==='character'||kind==='parenthetical'?'dialogue':kind==='dialogue'?'character':kind==='lyrics'?'lyrics':'action';event.preventDefault();if(!empty||kind==='action')document.execCommand('insertParagraph');format(next);}
  });
  attachCompletions(text,paragraph,characters,changed);
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
  return [...Object.entries(document.project.characterData||{}).map(([key,value])=>value.name||key),...document.project.frontstageWhiteboard.beats.flatMap(b=>b.characters||[])];
}
// Each control resolves its scene on every edit so simultaneous popups cannot overwrite another scene.
export function sluglineFields(getScene, getScenes, commit, editable=true) {
  const root=document.createElement('div');root.className='slugline-fields';root.setAttribute('aria-label','Slugline');
  const caption=document.createElement('strong');caption.textContent='SLUGLINE';root.append(caption);
  for(const [key,label,fallback,options] of [['prefix','INT. / EXT.','INT.',['INT.','EXT.','INT./EXT.','EXT./INT.']],['location','Location','',getScenes().map(s=>s.slug?.location).filter(Boolean)],['time','DAY / NIGHT','DAY',['DAY','NIGHT','DAWN','DUSK','MORNING','AFTERNOON','EVENING','LATER','CONTINUOUS','SAME TIME']]]) {
    const wrap=document.createElement('label');wrap.textContent=label;
    const input=document.createElement('input');input.setAttribute('aria-label',label);input.dataset.slugKey=key;input.value=getScene()?.slug?.[key]??fallback;input.disabled=!editable||!!getScene()?.frontstageTextLocked;
    const list=document.createElement('datalist');list.id='slug-options-'+crypto.randomUUID();for(const value of [...new Set(options)])list.append(new Option(value,value));input.setAttribute('list',list.id);
    input.onchange=()=>commit(()=>{const scene=getScene();if(!scene||scene.frontstageTextLocked)throw Error('Unlock the scene heading before changing it.');(scene.slug||={})[key]=input.value;});
    const combo=document.createElement('div');combo.className='slugline-combo';combo.append(input);wrap.append(combo,list);root.append(wrap);
  }
  root.refresh=()=>{const scene=getScene();for(const choice of root.querySelectorAll('[data-slug-options]'))choice.disabled=!editable||!!scene?.frontstageTextLocked;for(const input of root.querySelectorAll('[data-slug-key]')){input.disabled=!editable||!!scene?.frontstageTextLocked;if(document.activeElement!==input)input.value=scene?.slug?.[input.dataset.slugKey]??(input.dataset.slugKey==='prefix'?'INT.':input.dataset.slugKey==='time'?'DAY':'');}};
  return root;
}

function attachCompletions(text,paragraph,characters,changed) {
  let popup=null,values=[],index=0,line=null;
  const close=()=>{popup?.remove();popup=null;values=[];};
  const choose=()=>{if(!line||!values[index])return;const value=values[index];close();text.focus();const range=document.createRange();range.selectNodeContents(line);const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);document.execCommand('insertText',false,value);changed();};
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
  text.addEventListener('keydown',event=>{if(!popup||event.isComposing)return;if(['ArrowDown','ArrowUp','Enter','Tab','Escape'].includes(event.key)){event.preventDefault();event.stopImmediatePropagation();if(event.key==='Escape')close();else if(['Enter','Tab'].includes(event.key))choose();else{index=(index+(event.key==='ArrowDown'?1:values.length-1))%values.length;highlight();}}},true);
  text.addEventListener('blur',close);text.addEventListener('compositionstart',close);
}
