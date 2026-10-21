export const elements = ['action','character','dialogue','parenthetical','transition','shot','lyrics'];
export function screenplayToolbar(text, changed, editable=true) {
  const bar=document.createElement('div');bar.className='screenplay-toolbar';
  const select=document.createElement('select');select.setAttribute('aria-label','Element');
  for(const key of elements){const o=document.createElement('option');o.value=key;o.textContent=key[0].toUpperCase()+key.slice(1);select.append(o);}
  const paragraph=()=>{let node=window.getSelection()?.anchorNode;if(node?.nodeType===3)node=node.parentElement;if(!node||!text.contains(node))return null;while(node!==text&&node.parentElement!==text)node=node.parentElement;return node;};
  const format=kind=>{text.focus();let node=paragraph();if(node===text){document.execCommand('formatBlock',false,'p');node=paragraph();}if(node&&node!==text){node.className=`sc-line sc-${kind}`;select.value=kind;changed();}};
  select.onchange=()=>format(select.value);select.disabled=!editable;bar.append(select);
  for(const command of ['bold','italic','underline']){const b=document.createElement('button');b.textContent=command==='bold'?'B':command==='italic'?'I':'U';b.setAttribute('aria-label',command);b.disabled=!editable;b.onpointerdown=e=>e.preventDefault();b.onclick=()=>{text.focus();document.execCommand(command);changed();};bar.append(b);}
  text.addEventListener('keyup',()=>{const node=paragraph();if(node)select.value=elements.find(e=>node.classList.contains('sc-'+e))||'action';});
  text.addEventListener('keydown',event=>{
    if(event.isComposing||!editable)return;
    if(event.key==='Tab'){event.preventDefault();format(elements[(elements.indexOf(select.value)+(event.shiftKey?6:1))%7]);}
    if(event.altKey&&/^[1-7]$/.test(event.key)){event.preventDefault();format(elements[Number(event.key)-1]);}
    if(event.key==='Enter'&&!event.shiftKey){const node=paragraph(),kind=elements.find(e=>node?.classList.contains('sc-'+e))||'action',empty=!node?.textContent.trim(),next=empty?'action':kind==='character'||kind==='parenthetical'?'dialogue':kind==='dialogue'?'character':kind==='lyrics'?'lyrics':'action';event.preventDefault();if(!empty||kind==='action')document.execCommand('insertParagraph');format(next);}
  });
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
