import {sceneChanged} from './production-revision.js';
import {layoutDualDialogue,validateDualSplit} from './dual-dialogue.js';
import {pullOutBeats,replaceDocument} from './script-inclusion.js';
import * as model from './workspace-model.js';
import {blockLocked} from './board-operations.js';
import {screenplayToolbar,characterNames,elements,screenplaySelection,restoreScreenplaySelection} from './screenplay-editor.js';
import {decorateDialogue,projectDialogue} from './dialogue-rules.js';
export function parseHeading(text){const source=text.trim().toUpperCase(),prefix=['INT./EXT.','EXT./INT.','INT.','EXT.','I/E.'].find(p=>source.startsWith(p))||'',rest=source.slice(prefix.length).trim(),split=[...rest.matchAll(/\s+[-–—]\s*/g)].at(-1);return {prefix,location:split?rest.slice(0,split.index):rest,time:split?rest.slice(split.index+split[0].length):''};}
export function applyScriptDocument(document,html,headings){const b=model.board(document);for(const[id,value]of Object.entries(html)){const beat=b.beats.find(b=>b.id===id);if(!beat)throw Error('A screenplay beat no longer exists.');if(beat.html!==value&&(beat.locked||beat.omitted||blockLocked(b,beat.blockID)||model.scene(document,beat.sceneID).frontstageTextLocked))throw Error('This selection contains locked or inactive text.');}for(const[id,text]of Object.entries(headings)){const s=document.project.beats.find(s=>String(s.id)===id);if(!s)throw Error('Scene no longer exists.');const heading=parseHeading(text);if(s.frontstageTextLocked&&JSON.stringify(heading)!==JSON.stringify({prefix:s.slug?.prefix||'',location:s.slug?.location||'',time:s.slug?.time||''}))throw Error('Unlock the scene heading first.');s.slug={...s.slug,...heading};}for(const[id,value]of Object.entries(html))b.beats.find(b=>b.id===id).html=value;}
export function insertScriptScene(document,id,beforeHTML,afterHTML,heading){validateDualSplit(beforeHTML,afterHTML);const b=model.board(document),beat=b.beats.find(b=>b.id===id);if(!beat||beat.locked||beat.omitted||b.layers.find(l=>l.id===b.blocks.find(block=>block.id===beat.blockID)?.layerID)?.unused||blockLocked(b,beat.blockID)||model.scene(document,beat.sceneID).frontstageTextLocked)throw Error('Select an unlocked active beat.');const ordered=[...b.beats].sort((a,b)=>a.order-b.order),index=ordered.indexOf(beat),sceneID=Math.max(document.project.nextId||1,...document.project.beats.map(s=>s.id+1));const s={id:sceneID,title:'Untitled Scene',summary:'',content:'',slug:parseHeading(heading)};document.project.beats.push(s);document.project.nextId=sceneID+1;
 const fragment={...structuredClone(beat),id:crypto.randomUUID(),sceneID,title:'Untitled Beat',synopsis:'',html:afterHTML,order:(beat.order+(ordered[index+1]?.order??beat.order+2))/2,duration:Math.max(.05,beat.duration/2),start:beat.start+beat.duration/2};beat.html=beforeHTML;beat.duration=Math.max(.05,beat.duration/2);
 for(const next of ordered.slice(index+1)){if(next.sceneID!==beat.sceneID)break;if(next.locked||blockLocked(b,next.blockID))throw Error('A locked beat prevents inserting this scene.');next.sceneID=sceneID;}const owner=b.blocks.find(block=>block.id===beat.blockID);if(owner?.standalone){const container=structuredClone(owner);container.id=crypto.randomUUID();container.position.y+=60;b.blocks.push(container);fragment.blockID=container.id;}b.beats.push(fragment);return fragment.id;}
export function centerScriptTarget(node) {
  const desk=node?.closest('.continuous-desk');if(!desk)return;
  const viewport=desk.getBoundingClientRect(),target=node.getBoundingClientRect();
  desk.scrollTop=Math.max(0,Math.min(desk.scrollHeight-desk.clientHeight,desk.scrollTop+target.top+target.height/2-viewport.top-desk.clientTop-desk.clientHeight/2));
}
export function mountContinuousScript(sheet, api) {
  sheet.replaceChildren();
  sheet.classList.add('script-text', 'continuous-editor');
  sheet.contentEditable = String(!api.readonly());
  sheet.setAttribute('role', 'textbox');
  sheet.setAttribute('aria-label', 'Screenplay');
  const visible = new Set(), headingIDs = new Set();
  const dialogueCache=new Map();
  const refreshDialogue=()=>{decorateDialogue(sheet,null,projectDialogue(api.document(),dialogueCache).flags);layoutDualDialogue(sheet);};
  let composing = false, committing = false, lastOwner = null, pendingPullouts = new Set(), pendingHeading = null, beforeEditSelection=null;
  const board = () => model.board(api.document());
  const beatFor = id => board().beats.find(beat => beat.id === id);
  const locked = beat => !beat || beat.locked || blockLocked(board(), beat.blockID) || model.scene(api.document(), beat.sceneID).frontstageTextLocked;
  const ownerScene = node => beatFor(node.dataset.beatId)?.sceneID;
  const inlineHeading = scene => [scene.slug?.prefix ?? 'INT.', scene.slug?.location ?? '', scene.slug?.time ? '- '+scene.slug.time : ''].join(' ').replace(/\s+/g,' ').trim();
  for (const segment of model.scriptSegments(api.document())) {
    const beats = segment.beatIDs.map(beatFor).filter(api.matches);
    if (!beats.length) continue;
    const heading = document.createElement('p');
    heading.className = 'sc-line sc-slugline';
    heading.dataset.headingScene = segment.scene.id;
    heading.dataset.beatId = beats[0].id;
    heading.textContent = inlineHeading(segment.scene);
    if (locked(beats[0])) heading.contentEditable = 'false';
    sheet.append(heading); headingIDs.add(String(segment.scene.id));
    for (const beat of beats) {
      visible.add(beat.id);
      const template = document.createElement('template');
      template.innerHTML = api.cleanHTML(beat.html) || '<p class="sc-line sc-action"><br></p>';
      for (const source of [...template.content.childNodes]) {
        const paragraph = source.nodeType === 1 ? source : document.createElement('p');
        if (source.nodeType !== 1) paragraph.textContent = source.textContent;
        paragraph.dataset.beatId = beat.id;
        if (!paragraph.className) paragraph.className = 'sc-line sc-action';
        if (locked(beat)) paragraph.contentEditable = 'false';
        sheet.append(paragraph);
      }
    }
  }
  const paragraph = () => {
    let node = getSelection()?.anchorNode;
    if (node?.nodeType === 3) node = node.parentElement;
    if (!node || !sheet.contains(node)) return null;
    while (node !== sheet && node.parentElement !== sheet) node = node.parentElement;
    return node === sheet ? null : node;
  };
  function select() {
    if(composing)return;
    syncHeadings(document.activeElement===sheet?paragraph():null);
    const node = paragraph(), beat = beatFor(node?.dataset.beatId);
    if (beat) { lastOwner = beat.id; mark(beat.id); api.select(beat.sceneID, beat.id); }
    api.element?.(elements.find(kind => node?.classList.contains('sc-'+kind)) || 'action');
  }
  function mark(id) {
    sheet.dataset.activeBeat=id;
    for(const node of sheet.querySelectorAll('[data-active-heading]'))delete node.dataset.activeHeading;
    let node=[...sheet.children].find(node=>node.dataset.beatId===id);
    while(node&&!node.dataset.headingScene)node=node.previousElementSibling;
    if(node)node.dataset.activeHeading='true';
  }
  function syncHeadings(editing) {
    if(composing)return;
    for(const node of sheet.querySelectorAll('[data-heading-scene]')){
      const scene=api.document().project.beats.find(s=>String(s.id)===node.dataset.headingScene);
      if(scene&&sceneChanged(api.document(),scene.id))node.dataset.revised='true';else delete node.dataset.revised;
      if(!scene||node===editing||node.textContent===inlineHeading(scene))continue;
      const selection=getSelection(),inside=selection?.rangeCount&&node.contains(selection.anchorNode)&&node.contains(selection.focusNode);
      const offset=(container,index)=>{const r=document.createRange();r.selectNodeContents(node);r.setEnd(container,index);return r.toString().length;};
      const anchor=inside?offset(selection.anchorNode,selection.anchorOffset):0,focus=inside?offset(selection.focusNode,selection.focusOffset):0;
      node.textContent=inlineHeading(scene);if(!node.firstChild)node.append(document.createTextNode(''));
      if(inside)selection.setBaseAndExtent(node.firstChild,Math.min(anchor,node.textContent.length),node.firstChild,Math.min(focus,node.textContent.length));
    }
  }
  function splitScene() {
    if(composing||sheet.isComposing)return;
    const node=paragraph(),selection=getSelection();
    if(!node||node.dataset.headingScene||!selection?.isCollapsed||locked(beatFor(node.dataset.beatId)))throw Error('Place the cursor inside unlocked screenplay text to split the scene.');
    const id=node.dataset.beatId,parts=[...sheet.children].filter(n=>n.dataset.beatId===id&&!n.dataset.headingScene),caret=selection.getRangeAt(0),full=document.createRange();
    full.setStart(parts[0],0);full.setEnd(parts.at(-1),parts.at(-1).childNodes.length);
    const before=full.cloneRange(),after=full.cloneRange();before.setEnd(caret.startContainer,caret.startOffset);after.setStart(caret.startContainer,caret.startOffset);
    const first=document.createElement('div'),second=document.createElement('div');first.append(before.cloneContents());second.append(after.cloneContents());
    if(!first.textContent.trim()||!second.textContent.trim())throw Error('Place the cursor between screenplay text before splitting.');
    const scene=api.document().project.beats.find(s=>s.id===beatFor(id).sceneID);let created;
    const result=api.change(d=>{created=insertScriptScene(d,id,api.cleanHTML(first.innerHTML),api.cleanHTML(second.innerHTML),inlineHeading(scene));});
    if(result!==false){const beat=model.board(api.document()).beats.find(b=>b.id===created);api.select(beat.sceneID,created);api.rebuild?.();requestAnimationFrame(()=>{const node=document.querySelector('.continuous-editor>[data-beat-id="'+CSS.escape(created)+'"]');if(node){const editor=node.closest('.continuous-editor');editor.focus();const range=document.createRange();range.selectNodeContents(node);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);node.scrollIntoView({block:'nearest'});editor.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));}});}
  }
  function sceneAfterTransition(node) {
    if(composing||sheet.isComposing||!node)return;
    if(locked(beatFor(node.dataset.beatId))){api.status('Unlock this scene before creating a new scene.');return;}
    if(commit()===false)return;
    const next=node.nextElementSibling;
    const focusHeading=id=>{api.rebuild?.();const heading=document.querySelector('.continuous-editor>[data-heading-scene][data-beat-id="'+CSS.escape(id)+'"]');if(heading){const editor=heading.closest('.continuous-editor');editor.focus({preventScroll:true});const range=document.createRange();range.selectNodeContents(heading);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);heading.scrollIntoView({block:'nearest'});editor.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));}};
    if(next?.dataset.headingScene){const beat=beatFor(next.dataset.beatId),scene=api.document().project.beats.find(s=>s.id===beat?.sceneID);if(scene&&!locked(beat)&&!inlineHeading(scene).trim()){api.select(scene.id,beat.id);focusHeading(beat.id);return;}}
    const id=node.dataset.beatId,parts=[...sheet.children].filter(n=>n.dataset.beatId===id&&!n.dataset.headingScene),index=parts.indexOf(node);
    if(index<0)return;
    const first=parts.slice(0,index+1).map(n=>api.cleanHTML(n.outerHTML)).join(''),second=parts.slice(index+1).map(n=>api.cleanHTML(n.outerHTML)).join('');let created;
    const result=(api.structureChange||api.change)(d=>{created=insertScriptScene(d,id,first,second,'');});
    if(result!==false){const beat=beatFor(created);api.select(beat.sceneID,created);focusHeading(created);}
  }
  let contextCaret;
  sheet.addEventListener('pointerdown',event=>{if(event.button===2){const selection=getSelection();contextCaret=selection?.rangeCount&&sheet.contains(selection.anchorNode)&&sheet.contains(selection.focusNode)?selection.getRangeAt(0).cloneRange():null;}},true);
  sheet.addEventListener('contextmenu',event=>{
    if(api.readonly()||composing||sheet.isComposing)return;event.preventDefault();document.querySelector('.write-script-menu')?.remove();
    if(contextCaret&&sheet.contains(contextCaret.startContainer)){getSelection().removeAllRanges();getSelection().addRange(contextCaret);}
    const menu=document.createElement('div');menu.className='write-script-menu';menu.setAttribute('role','menu');menu.style.left=event.clientX+'px';menu.style.top=event.clientY+'px';
    const target=event.target.closest('[data-beat-id]'),id=target?.dataset.beatId||paragraph()?.dataset.beatId;
    const item=(label,action)=>{const button=document.createElement('button');button.textContent=label;button.setAttribute('role','menuitem');button.onmousedown=e=>e.preventDefault();button.onclick=()=>{menu.remove();try{action();}catch(e){api.status(e.message);}};menu.append(button);};
    item('Undo',()=>api.undo?.());item('Redo',()=>api.redo?.());
    for(const command of ['cut','copy'])item(command[0].toUpperCase()+command.slice(1),()=>{if(!document.execCommand(command))api.status('Use Command/Ctrl+'+(command==='cut'?'X':'C')+'.');});
    item('Paste',async()=>{try{const value=await navigator.clipboard.readText();sheet.focus({preventScroll:true});if(contextCaret?.startContainer.isConnected){getSelection().removeAllRanges();getSelection().addRange(contextCaret);}document.execCommand('insertText',false,value);}catch{api.status('Use Command/Ctrl+V to paste into the screenplay.');}});
    item('Select All',()=>{sheet.focus({preventScroll:true});const range=document.createRange();range.selectNodeContents(sheet);getSelection().removeAllRanges();getSelection().addRange(range);});
    for(const kind of elements)item(kind==='slugline'?'Scene Heading':kind[0].toUpperCase()+kind.slice(1),()=>behavior.format(kind));
    item('Pair / Unpair Dual Dialogue',()=>sheet.toggleDualDialogue?.());item('Split scene at cursor',splitScene);item('Duplicate Beat',()=>{if(id)api.duplicate?.(id);});item('Open Beat Editor',()=>{if(id)api.open?.(id);});
    document.body.append(menu);const bounds=menu.getBoundingClientRect();menu.style.top=Math.max(4,Math.min(event.clientY,innerHeight-bounds.height-4))+'px';menu.style.left=Math.max(4,Math.min(event.clientX,innerWidth-bounds.width-4))+'px';
    const dismiss=()=>{menu.remove();document.removeEventListener('pointerdown',outside,true);document.removeEventListener('keydown',keys,true);};
    const outside=e=>{if(!menu.contains(e.target))dismiss();},keys=e=>{if(e.key==='Escape'){e.preventDefault();dismiss();}};
    menu.addEventListener('click',dismiss);document.addEventListener('pointerdown',outside,true);document.addEventListener('keydown',keys,true);
  });
  function restoreHeadingAnchors(headings) {
    for (const sceneID of headingIDs) {
      if ([...pendingPullouts].some(id => String(beatFor(id)?.sceneID) === sceneID)) continue;
      if ([...sheet.children].some(node => node.dataset.headingScene === sceneID)) continue;
      const first = [...sheet.children].find(node => String(ownerScene(node)) === sceneID);
      if (!first) continue;
      const heading = document.createElement('p');
      heading.className = 'sc-line sc-slugline'; heading.dataset.headingScene = sceneID;
      heading.dataset.beatId = first.dataset.beatId; heading.innerHTML = '<br>';
      first.before(heading); headings[sceneID] = '';
    }
  }
  let acceptedHTML = sheet.innerHTML;
  const headingBaseline=new WeakMap();let bodyBaseline=new Map();
  function acceptBaseline(){bodyBaseline=new Map();for(const node of sheet.children){if(node.dataset.headingScene)headingBaseline.set(node,node.textContent);else if(node.dataset.beatId)bodyBaseline.set(node.dataset.beatId,(bodyBaseline.get(node.dataset.beatId)||'')+api.cleanHTML(node.outerHTML));}}
  acceptBaseline();
  function rollback(bookmark){const desk=sheet.closest('.continuous-desk'),position=desk&&{x:desk.scrollLeft,y:desk.scrollTop};sheet.innerHTML=acceptedHTML;restoreScreenplaySelection(sheet,bookmark);if(position){desk.scrollLeft=position.x;desk.scrollTop=position.y;}acceptBaseline();}
  function commit(meta) {
    if (composing || committing) return;
    committing = true;
    const bookmark=beforeEditSelection||screenplaySelection(sheet);
    const placements = [], newHeadings = [];
    try {
      const headings = {};
      restoreHeadingAnchors(headings);
      const success = (meta?.command&&api.structureChange||api.change)(document => {
        const html = Object.fromEntries([...visible].filter(id => !pendingPullouts.has(id)).map(id => [id, '']));
        const redirects = new Map(); let owner = null;
        for (const node of [...sheet.children]) {
          const original = node.dataset.beatId || owner || lastOwner;
          owner = redirects.get(original) || original;
          if (!owner || pendingPullouts.has(owner)) continue;
          if (node.dataset.headingScene) {
            const id=node.dataset.headingScene,scene=document.project.beats.find(scene=>String(scene.id)===id);
            // The edited occurrence wins over unchanged legacy repetitions.
            if (node.textContent!==headingBaseline.get(node)&&(!(id in headings)||node===paragraph())) headings[id]=node.textContent;
            continue;
          }
          if (node.classList.contains('sc-slugline') && node.textContent.trim()) {
            const newID = insertScriptScene(document, owner, html[owner] || '', '', node.textContent);
            const beat = model.board(document).beats.find(beat => beat.id === newID);
            redirects.set(original, newID); redirects.set(owner, newID);
            html[newID] = ''; owner = newID;
            newHeadings.push({node, id: newID, sceneID: beat.sceneID});
          } else {
            html[owner] = (html[owner] || '') + api.cleanHTML(node.outerHTML);
            placements.push({node, id: owner});
          }
        }
        const changedHTML=Object.fromEntries(Object.entries(html).filter(([id,value])=>value!==bodyBaseline.get(id)));
        applyScriptDocument(document, changedHTML, headings);
        if (pendingPullouts.size) replaceDocument(document, pullOutBeats(document, pendingPullouts));
      });
      if (success === false) { rollback(bookmark); return false; }
      for (const {node,id} of placements) node.dataset.beatId = id;
      for (const {node,id,sceneID} of newHeadings) {
        node.dataset.beatId = id; node.dataset.headingScene = sceneID;
        visible.add(id); headingIDs.add(String(sceneID));
      }
      for (const id of pendingPullouts) visible.delete(id);
      syncHeadings(paragraph());
      acceptedHTML = sheet.innerHTML;
      acceptBaseline();
    } catch (error) { rollback(bookmark); api.status(error.message); return false; }
    finally { beforeEditSelection=null;pendingPullouts.clear(); committing = false; refreshDialogue();select(); }
  }
  const behavior = screenplayToolbar(sheet, commit, !api.readonly(), () => characterNames(api.document(),paragraph()?.dataset.beatId), () => api.document().project.beats.filter(s=>String(s.id)!==paragraph()?.dataset.headingScene).map(inlineHeading), {status:api.status,continuationFlags:()=>projectDialogue(api.document(),dialogueCache).flags,newScene:sceneAfterTransition}).editor;
  sheet.addEventListener('compositionstart', () => { composing = true; sheet.isComposing = true; });
  sheet.addEventListener('compositionend', () => { composing = false; sheet.isComposing = false; commit(); });
  sheet.addEventListener('input', event => {
    if (event.isComposing || composing) return;
    if(pendingHeading){
      const {node,index,sceneID,beatID}=pendingHeading,target=sheet.contains(node)?node:sheet.children[index];
      if(target){target.dataset.headingScene=sceneID;target.dataset.beatId=beatID;target.className='sc-line sc-slugline';}
      pendingHeading=null;
    }
    const node = paragraph();
    if (node && !node.dataset.headingScene && node.classList.contains('sc-action') && /^(INT\.|EXT\.|INT\.\/EXT\.|EXT\.\/INT\.)\s/i.test(node.textContent)) node.className = 'sc-line sc-slugline';
    commit();
  });
  function insertAfterHeading(node, kind = 'action') {
    syncHeadings(null);
    const following=node.nextElementSibling;
    if(kind==='action'&&following?.dataset.beatId===node.dataset.beatId&&!following.dataset.headingScene){
      const range=document.createRange();range.selectNodeContents(following);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);select();return;
    }
    const next = document.createElement('p'); next.className = 'sc-line sc-'+kind;
    next.dataset.beatId = node.dataset.beatId; next.innerHTML = '<br>'; node.after(next);
    const range = document.createRange(); range.selectNodeContents(next); range.collapse(true);
    getSelection().removeAllRanges(); getSelection().addRange(range); commit();
  }
  sheet.addEventListener('keydown', event => {
    if (event.isComposing) return;
    if(event.key==='Enter'&&(event.metaKey||event.ctrlKey)){if(paragraph()?.dataset.headingScene){event.preventDefault();event.stopImmediatePropagation();insertAfterHeading(paragraph());}return;}
    // Completion's capture handler gets first use of navigation/acceptance keys.
    if (document.querySelector('.autofill-list')) return;
    const node = paragraph();
    if (event.key === 'Backspace' && node?.dataset.headingScene && getSelection()?.isCollapsed && getSelection().anchorOffset === 0) {
      event.preventDefault(); event.stopImmediatePropagation(); return;
    }
    if (event.key === 'Enter' && node?.dataset.headingScene) {
      event.preventDefault(); event.stopImmediatePropagation(); insertAfterHeading(node);
    }
  }, true);
  sheet.addEventListener('beforeinput', event => {
    if (composing) return;
    beforeEditSelection??=screenplaySelection(sheet);
    const selection = getSelection(); if (!selection?.rangeCount) return;
    const range = selection.getRangeAt(0), touched = [...sheet.children].filter(node => range.intersectsNode(node));
    if (touched.some(node => locked(beatFor(node.dataset.beatId)))) {
      event.preventDefault(); pendingPullouts.clear(); api.status('This selection contains locked text.'); return;
    }
    pendingPullouts.clear();pendingHeading=null;
    if(range.collapsed&&event.inputType?.startsWith('delete')){
      const node=paragraph();if(node){const before=document.createRange();before.selectNodeContents(node);before.setEnd(range.startContainer,range.startOffset);const offset=before.toString().length;
        if((event.inputType.endsWith('Forward')&&node.dataset.headingScene&&offset===node.textContent.length)||(event.inputType.endsWith('Backward')&&offset===0&&(node.dataset.headingScene||node.previousElementSibling?.dataset.headingScene))){event.preventDefault();return;}
      }
    }
    const heading=touched.length===1&&touched[0].dataset.headingScene?touched[0]:null;
    if(heading&&!['insertParagraph','insertLineBreak','historyUndo','historyRedo'].includes(event.inputType)&&!/[\r\n]/.test(event.data||'')){
      pendingHeading={node:heading,index:[...sheet.children].indexOf(heading),sceneID:heading.dataset.headingScene,beatID:heading.dataset.beatId};
      return;
    }
    if (!event.inputType?.startsWith('delete') || range.collapsed) return;
    for (const sceneID of headingIDs) {
      const owned = board().beats.filter(beat => String(beat.sceneID) === sceneID && !beat.omitted);
      const nodes = [...sheet.children].filter(node => owned.some(beat => beat.id === node.dataset.beatId));
      if (!nodes.length || !owned.every(beat => visible.has(beat.id))) continue;
      const full = document.createRange(); full.setStart(nodes[0], 0); full.setEnd(nodes.at(-1), nodes.at(-1).childNodes.length);
      if (range.compareBoundaryPoints(Range.START_TO_START, full) <= 0 && range.compareBoundaryPoints(Range.END_TO_END, full) >= 0) owned.forEach(beat => pendingPullouts.add(beat.id));
    }
  });
  sheet.addEventListener('paste',event=>{
    if(composing||api.readonly()||!paragraph()?.dataset.headingScene)return;
    const range=getSelection()?.getRangeAt(0),node=paragraph();if(!range||!node.contains(range.endContainer))return;
    if(locked(beatFor(node.dataset.beatId)))return;
    event.preventDefault();document.execCommand('insertText',false,(event.clipboardData?.getData('text/plain')||'').replace(/[\r\n]+/g,' '));
  });
  // Never mutate a subtree synchronously while a page rebuild is removing it.
  sheet.addEventListener('blur',()=>queueMicrotask(()=>{if(sheet.isConnected&&!sheet.closest('.write-center')?.inert){syncHeadings(null);acceptedHTML=sheet.innerHTML;}}));
  for (const event of ['focus','keyup','mouseup']) sheet.addEventListener(event, select);
  refreshDialogue();
  if(api.selection?.())mark(api.selection());
  return {...behavior,split:splitScene, format(kind) { const node = paragraph(); if (node?.dataset.headingScene && kind !== 'slugline') insertAfterHeading(node, kind); else behavior.format(kind); }, commit,
    reveal(id,focus=true) { if(composing)return false;commit();syncHeadings(null);const node = [...sheet.children].find(node => node.dataset.beatId === id); if(node){const range=document.createRange();range.selectNodeContents(node);range.collapse(true);getSelection().removeAllRanges();getSelection().addRange(range);if(focus&&!sheet.closest('.write-center')?.inert)sheet.focus({preventScroll:true});mark(id);centerScriptTarget(node);} return !!node; }};
}
