import {blockLocked,validateBoard} from './board-operations.js';
// Lossless operations shared with FrontstageCore/DualDialogue.swift. Kept out of
// the editor until native/browser layout and export acceptance are complete.
const message='Select two adjacent character/dialogue passages in one beat. Each speech must contain dialogue.';
const fail=()=>{throw Error(message);};
const voids=new Set(['br','hr','img','input','meta','link','wbr','source','area','base','embed','param','col','track']);
const elements=['action','character','dialogue','parenthetical','transition','shot','lyrics','slugline'];
function roots(html){
  const output=[],stack=[];let current=null,cursor=0;
  for(const match of html.matchAll(/<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>/g)){
    if(!stack.length&&html.slice(cursor,match.index).trim())fail();
    cursor=match.index+match[0].length;
    const raw=match[0];if(raw.startsWith('<!--'))continue;
    const name=/^<\s*(\/?)\s*([a-zA-Z][a-zA-Z0-9]*)/.exec(raw);if(!name)fail();
    const key=name[2].toLowerCase();
    if(name[1]){
      if(stack.at(-1)!==key)fail();stack.pop();
      if(!stack.length&&current){current.contentEnd=match.index;current.end=cursor;output.push(current);current=null;}
    }else{
      if(!stack.length){
        if(!['p','div'].includes(key))fail();
        const classes=/\sclass\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i.exec(raw);
        current={start:match.index,end:cursor,contentStart:cursor,contentEnd:cursor,tag:key,classes:new Set((classes?.slice(1).find(v=>v!==undefined)||'').split(/\s+/))};
        const matches=elements.filter(e=>current.classes.has('sc-'+e));
        current.element=current.classes.has('sc-dual')||current.classes.has('sc-dual-column')||matches.length!==1?null:matches[0];
      }else if(['p','div','table','ul','ol','li','blockquote'].includes(key)&&!current?.classes.has('sc-dual')&&!current?.classes.has('sc-dual-column'))fail();
      if(!voids.has(key)){if(raw.endsWith('/>')||stack.length>=64)fail();stack.push(key);}
    }
  }
  if(stack.length||html.slice(cursor).trim())fail();return output;
}
function validateColumn(html){
  const nodes=roots(html);
  const hasText=node=>!!html.slice(node.contentStart,node.contentEnd).replace(/<!--[\s\S]*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>/g,'').replace(/&nbsp;|&#160;/g,' ').trim();
  if(nodes[0]?.element!=='character'||!hasText(nodes[0])||!nodes.slice(1).every(n=>['dialogue','parenthetical'].includes(n.element))||!nodes.slice(1).some(n=>n.element==='dialogue'&&hasText(n)))fail();
}
export function dialoguePairHTML(left,right){
  validateColumn(left);validateColumn(right);
  return `<div class="sc-dual"><div class="sc-dual-column sc-dual-left">${left}</div><div class="sc-dual-column sc-dual-right">${right}</div></div>`;
}
function readPair(node,html){
  if(!node.classes.has('sc-dual'))return null;
  const body=html.slice(node.contentStart,node.contentEnd),columns=roots(body);
  if(node.tag!=='div'||columns.length!==2||!columns.every(c=>c.tag==='div'&&c.classes.has('sc-dual-column'))||!columns[0].classes.has('sc-dual-left')||columns[0].classes.has('sc-dual-right')||!columns[1].classes.has('sc-dual-right')||columns[1].classes.has('sc-dual-left'))fail();
  const left=body.slice(columns[0].contentStart,columns[0].contentEnd),right=body.slice(columns[1].contentStart,columns[1].contentEnd);
  validateColumn(left);validateColumn(right);return {left,right};
}
export function dialoguePairs(html){return roots(html).map(n=>readPair(n,html)).filter(Boolean);}
export function pairDialogueHTML(html,firstCue,secondCue){
  const nodes=roots(html);
  if(!Number.isInteger(firstCue)||!Number.isInteger(secondCue)||firstCue<0||secondCue<=firstCue||secondCue>=nodes.length)fail();
  let end=secondCue+1;while(end<nodes.length&&['dialogue','parenthetical'].includes(nodes[end].element))end++;
  const start=nodes[firstCue].start,finish=nodes[end-1].end;
  return html.slice(0,start)+dialoguePairHTML(html.slice(start,nodes[secondCue].start),html.slice(nodes[secondCue].start,finish))+html.slice(finish);
}
export function removeDualDialogueHTML(html,index){
  const nodes=roots(html);if(!Number.isInteger(index)||!nodes[index])fail();
  const node=nodes[index];if(!readPair(node,html))fail();
  const body=html.slice(node.contentStart,node.contentEnd);let unwrapped=body;
  for(const column of roots(body).reverse())unwrapped=unwrapped.slice(0,column.start)+body.slice(column.contentStart,column.contentEnd)+unwrapped.slice(column.end);
  return html.slice(0,node.start)+unwrapped+html.slice(node.end);
}

// Return a candidate, leaving the caller's document untouched on success or
// rejection. The existing workspace edit transaction supplies undo and saving.
function updateDialogue(document,beatID,transform){
  const next=structuredClone(document),project=next.project,board=project.frontstageWhiteboard;
  const beat=board?.beats.find(b=>b.id===beatID),scene=project.beats.find(s=>s.id===beat?.sceneID);
  const block=board?.blocks.find(b=>b.id===beat?.blockID),layer=board?.layers.find(l=>l.id===block?.layerID);
  if(!beat||!scene||!block||!layer||beat.locked||beat.omitted||layer.unused||blockLocked(board,beat.blockID)||scene.frontstageTextLocked)throw Error('This selection contains locked or inactive text.');
  const active=board.beats.filter(b=>b.sceneID===scene.id&&!b.omitted&&!board.layers.find(l=>l.id===board.blocks.find(c=>c.id===b.blockID)?.layerID)?.unused).sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id));
  if(active.map(b=>b.html).join('')!==scene.content)throw Error('The scene script differs from its linked snippets. Reconcile the source text before editing.');
  beat.html=transform(beat.html);scene.content=active.map(b=>b.html).join('');
  validateBoard(board,new Set(project.beats.map(s=>s.id)));return next;
}
export function pairDialogue(document,beatID,firstCue,secondCue){return updateDialogue(document,beatID,html=>pairDialogueHTML(html,firstCue,secondCue));}
export function removeDualDialogue(document,beatID,index){return updateDialogue(document,beatID,html=>removeDualDialogueHTML(html,index));}
