import {characterCue} from './dialogue-rules.js';
const kinds=['slugline','action','character','dialogue','parenthetical','transition','shot','lyrics'];
const kind=node=>kinds.find(k=>node.classList.contains('sc-'+k))||'action';
const pairKey=node=>node.dataset.dualPair?(node.dataset.beatId||'popup')+':'+node.dataset.dualPair:null;
const lines=root=>[...root.children].filter(n=>n.nodeType===1);
export function dualPairPlan(values,index){
 if(index<0||index>=values.length)throw Error('Select the second speech block.');
 let cue=index;while(cue>0&&['dialogue','parenthetical'].includes(values[cue].element))cue--;
 if(values[cue].element!=='character'||!characterCue(values[cue].text).name)throw Error('Select a complete character and dialogue block.');
 const end=start=>{let i=start+1,spoken=false;while(i<values.length&&['dialogue','parenthetical'].includes(values[i].element)){if(values[i].scene!==values[start].scene)throw Error('Dual dialogue must stay within one scene.');if(values[i].element==='dialogue'&&values[i].text.trim())spoken=true;i++;}if(!spoken)throw Error('Both characters need dialogue before pairing.');return i;};
 const rightEnd=end(cue);if(cue===0)throw Error('A preceding speech block is required.');let left=cue-1;while(left>0&&['dialogue','parenthetical'].includes(values[left].element))left--;
 if(values[left].element!=='character'||!characterCue(values[left].text).name||values[left].scene!==values[cue].scene||end(left)!==cue)throw Error('Pair adjacent speech blocks in the same scene. Intervening action cannot be paired.');
 return {left:[left,cue],right:[cue,rightEnd]};
}
const values=nodes=>nodes.map(n=>({element:kind(n),text:n.textContent,scene:n.dataset.beatId||'popup'}));
export function reconcileDualDialogue(root){
 const nodes=lines(root),data=values(nodes);
 for(const id of new Set(nodes.map(pairKey).filter(Boolean))){const indices=nodes.flatMap((n,i)=>pairKey(n)===id?[i]:[]),right=indices.find(i=>nodes[i].classList.contains('sc-dual-right'));let valid=false;
  try{const p=dualPairPlan(data,right??-1);valid=indices.length===p.right[1]-p.left[0]&&indices.every((v,i)=>v===p.left[0]+i)&&indices.every(i=>nodes[i].classList.contains(i<p.right[0]?'sc-dual-left':'sc-dual-right'));}catch{}
  if(!valid)for(const i of indices){delete nodes[i].dataset.dualPair;nodes[i].classList.remove('sc-dual-left','sc-dual-right');}
 }
}
export function toggleDualDialogue(root){
 if(!root.isContentEditable||root.isComposing) return;
 const selection=getSelection();let node=selection?.anchorNode;if(node?.nodeType===3)node=node.parentElement;while(node&&node!==root&&node.parentElement!==root)node=node.parentElement;
 const nodes=lines(root),index=nodes.indexOf(node);if(index<0)throw Error('Select the second speech block.');
 if(node.dataset.dualPair){const id=pairKey(node);for(const n of nodes.filter(n=>pairKey(n)===id)){delete n.dataset.dualPair;n.classList.remove('sc-dual-left','sc-dual-right');}return;}
 const plan=dualPairPlan(values(nodes),index),id=crypto.randomUUID();
 for(let i=plan.left[0];i<plan.right[1];i++)if(nodes[i].contentEditable==='false'||nodes[i].dataset.dualPair||nodes[i].classList.contains('sc-dual-left')||nodes[i].classList.contains('sc-dual-right'))throw Error('Unlock or unpair existing dialogue before pairing.');
 for(const[range,side]of [[plan.left,'left'],[plan.right,'right']])for(let i=range[0];i<range[1];i++){nodes[i].dataset.dualPair=id;nodes[i].classList.add('sc-dual-'+side);}
}
const derived=['width','box-sizing','margin-left','margin-right','margin-top','margin-bottom','padding-left','padding-right'];
// Keep flat editable paragraphs: each column flows normally, then the right column's first
// paragraph moves to the shared top. The following paragraph starts below the taller column.
export function layoutDualDialogue(root){
 if(root.isComposing)return;
 for(const n of root.querySelectorAll('[data-dual-layout]')){for(const property of derived)n.style.removeProperty(property);delete n.dataset.dualLayout;}
 const nodes=lines(root),style=getComputedStyle(root),width=root.clientWidth-(parseFloat(style.paddingLeft)||0)-(parseFloat(style.paddingRight)||0);if(!width)return;
 for(const id of new Set(nodes.map(pairKey).filter(Boolean))){const pair=nodes.filter(n=>pairKey(n)===id),left=pair.filter(n=>n.classList.contains('sc-dual-left')),right=pair.filter(n=>n.classList.contains('sc-dual-right'));if(!left.length||!right.length)continue;
  const col=Math.max(1,(width-24)/2);
  for(const [column,side]of [[left,'left'],[right,'right']])for(const n of column){const element=kind(n),indent=element==='character'?.33:element==='dialogue'?.16:element==='parenthetical'?.25:0,trailing=element==='dialogue'?.16:element==='parenthetical'?.20:0;n.dataset.dualLayout='true';Object.assign(n.style,{width:col+'px',boxSizing:'border-box',marginLeft:(side==='right'?col+24:0)+'px',marginRight:'0px',paddingLeft:col*indent+'px',paddingRight:col*trailing+'px'});n.style.setProperty('margin-left',(side==='right'?col+24:0)+'px','important');n.style.setProperty('margin-right','0px','important');}
  const zoom=root.getBoundingClientRect().width/(root.offsetWidth||1)||1,top=left[0].getBoundingClientRect().top,bottom=left.at(-1).getBoundingClientRect().bottom;
  const first=right[0],margin=parseFloat(getComputedStyle(first).marginTop)||0;first.style.marginTop=(margin+(top-first.getBoundingClientRect().top)/zoom)+'px';
  const last=right.at(-1),after=parseFloat(getComputedStyle(last).marginBottom)||0;last.style.marginBottom=(after+Math.max(0,(bottom-last.getBoundingClientRect().bottom)/zoom))+'px';
 }
}
export function normalizeLegacyDualHTML(html){
 const root=new DOMParser().parseFromString(html,'text/html').body,nodes=[...root.querySelectorAll(kinds.map(k=>'.sc-'+k).join(','))].filter(n=>!n.querySelector(kinds.map(k=>'.sc-'+k).join(','))),data=values(nodes),covered=new Set();let pairs=0;
 for(const[i,n]of nodes.entries())if(n.classList.contains('sc-dual-right')&&kind(n)==='character'&&!n.dataset.dualPair&&!covered.has(i)){const p=dualPairPlan(data,i),id=crypto.randomUUID();for(const[range,side]of [[p.left,'left'],[p.right,'right']])for(let j=range[0];j<range[1];j++){if(nodes[j].dataset.dualPair||!nodes[j].classList.contains('sc-dual-'+side))throw Error('Legacy dual dialogue contains ambiguous annotations. The original is preserved.');nodes[j].dataset.dualPair=id;covered.add(j);}pairs++;}
 if(nodes.some((n,i)=>!n.dataset.dualPair&&(n.classList.contains('sc-dual-left')||n.classList.contains('sc-dual-right'))&&!covered.has(i)))throw Error('Legacy dual dialogue is incomplete. Review its speech blocks before conversion.');
 return {html:pairs?root.innerHTML:html,pairs};
}

export function duplicatedPairIDs(html){const ids=new Map();return html.replace(/\bdata-dual-pair\s*=\s*(["'])([^"']+)\1/gi,(match,quote,id)=>{if(!ids.has(id))ids.set(id,crypto.randomUUID());return match.replace(id,ids.get(id));});}
