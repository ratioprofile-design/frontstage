import {dualPairPlan} from './dual-dialogue.js';
import {scriptSegments,heading} from './workspace-model.js';
import {paragraphKind,scriptParagraphs,decorateDialogue} from './dialogue-rules.js';
const xml=text=>String(text).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const text=p=>p.runs.map(run=>run.text).join('');
export function interchangeParagraphs(document){
 const result=[],settings=document.project.frontstageScriptLayout||{};
 for(const segment of scriptSegments(document)){
  result.push({element:'slugline',runs:[{text:heading(segment.scene)+(segment.continuation?' (CONTINUED)':''),bold:false,italic:false,underline:false}],number:segment.number});
  const root=new DOMParser().parseFromString(segment.html||'','text/html').body;decorateDialogue(root);
  for(const line of scriptParagraphs(root)){
   const element=paragraphKind(line),override=settings.elements?.[element],runs=[];
   function walk(node,style){if(node.nodeType===3){runs.push({text:node.data,...style});return;}const next={...style};if(node.matches?.('b,strong'))next.bold=true;if(node.matches?.('i,em'))next.italic=true;if(node.matches?.('u'))next.underline=true;if(node.tagName==='BR'){runs.push({text:'\n',...next});return;}for(const child of node.childNodes)walk(child,next);}
   walk(line,{bold:override?.isBold??['slugline','transition','shot'].includes(element),italic:override?.isItalic??false,underline:override?.isUnderline??false});
   if(line.dataset.autoContinuation==='true')runs.push({text:" (CONT'D)",bold:false,italic:false,underline:false});
   result.push({element,runs,dualPair:line.dataset.dualPair||null,dualSide:line.classList.contains('sc-dual-left')?'left':line.classList.contains('sc-dual-right')?'right':null});
  }
 }
 return result;
}
function validatePair(values){const kinds=values.map(p=>p.element),right=values.findIndex(p=>p.dualSide==='right');if(right<=0||kinds[0]!=='character'||kinds[right]!=='character'||values.slice(0,right).some(p=>p.dualSide!=='left')||values.slice(right).some(p=>p.dualSide!=='right')||values.slice(1,right).some(p=>!['dialogue','parenthetical'].includes(p.element))||values.slice(right+1).some(p=>!['dialogue','parenthetical'].includes(p.element))||!values.slice(1,right).some(p=>p.element==='dialogue'&&text(p).trim())||!values.slice(right+1).some(p=>p.element==='dialogue'&&text(p).trim()))throw Error('Repair incomplete dual dialogue before exporting.');}
export function renderFDX(paragraphs){
 const paragraph=p=>`<Paragraph Type="${p.element==='slugline'?'Scene Heading':p.element[0].toUpperCase()+p.element.slice(1)}"${p.number!=null?` Number="${xml(p.number)}"`:''}>${p.runs.map(run=>{const style=[run.bold?'Bold':null,run.italic?'Italic':null,run.underline?'Underline':null].filter(Boolean).join('+');return `<Text${style?` Style="${style}"`:''}>${xml(run.text)}</Text>`;}).join('')}</Paragraph>`;
 let result='';for(let i=0;i<paragraphs.length;){const p=paragraphs[i];if(p.dualPair){let end=i+1;while(end<paragraphs.length&&paragraphs[end].dualPair===p.dualPair)end++;const values=paragraphs.slice(i,end);validatePair(values);result+='<Paragraph Type="General"><DualDialogue>'+values.map(paragraph).join('')+'</DualDialogue></Paragraph>';i=end;}else{if(p.dualSide)throw Error('Review legacy dual dialogue before exporting.');result+=paragraph(p);i++;}}
 return `<?xml version="1.0" encoding="UTF-8"?><FinalDraft DocumentType="Script" Template="No" Version="1"><Content>${result}</Content></FinalDraft>`;
}
export function renderFountain(paragraphs){
 renderFDX(paragraphs);const output=[];
 for(const[index,p]of paragraphs.entries()){
  const value=p.runs.map(run=>{let value=run.text.replaceAll('\\','\\\\').replaceAll('*','\\*').replaceAll('_','\\_');if(run.underline)value='_'+value+'_';if(run.italic)value='*'+value+'*';if(run.bold)value='**'+value+'**';return value;}).join('');
  if(p.element==='slugline')output.push('','.'+value+(p.number!=null?` #${p.number}#`:''),'');
  else if(p.element==='character')output.push('','@'+value+(p.dualSide==='right'?' ^':''));
  else if(p.element==='parenthetical')output.push((value.startsWith('(')?'':'(')+value+(value.endsWith(')')?'':')'));
  else if(p.element==='dialogue'){output.push(value);if(!['dialogue','parenthetical'].includes(paragraphs[index+1]?.element))output.push('');}
  else if(p.element==='transition')output.push('','> '+value,'');
  else if(p.element==='lyrics')output.push('~'+value);
  else if(p.element==='shot')output.push('','/* DOT element: shot */','!'+value,'');
  else output.push('','!'+value,'');
 }
 return output.join('\n').replace(/^\n+|\n+$/g,'')+'\n';
}

export function parseFDX(source){
 if(new TextEncoder().encode(source).length>32*1024*1024)throw Error('The script exceeds the 32 MB import limit.');
 const root=new DOMParser().parseFromString(source,'application/xml');if(root.querySelector('parsererror')||root.documentElement.tagName!=='FinalDraft'||root.documentElement.getAttribute('DocumentType')!=='Script')throw Error('The document is not a readable Final Draft script.');
 const result=[];
 const visit=(parent,pair=null)=>{let cues=0;for(const child of parent.children){if(child.tagName==='Paragraph'){
  const nested=child.querySelector(':scope > DualDialogue');if(nested){visit(nested,crypto.randomUUID());continue;}
  const type=child.getAttribute('Type'),element=type==='Scene Heading'?'slugline':(type||'Action').toLowerCase();if(element==='character')cues++;
  const runs=[...child.querySelectorAll(':scope > Text')].map(n=>{const style=n.getAttribute('Style')||'';return {text:n.textContent,bold:style.includes('Bold'),italic:style.includes('Italic'),underline:style.includes('Underline')};});
  result.push({element:['slugline','action','character','dialogue','parenthetical','transition','shot','lyrics'].includes(element)?element:'action',runs,number:child.getAttribute('Number')??child.querySelector('SceneProperties')?.getAttribute('Number')??null,dualPair:pair,dualSide:pair?(cues>1?'right':'left'):null});
 }}};const content=root.querySelector('Content');if(content)visit(content);renderFDX(result);return result;
}
function fountainRuns(source){const runs=[];let value='',bold=false,italic=false,underline=false;const flush=()=>{if(value){runs.push({text:value,bold,italic,underline});value='';}};for(let i=0;i<source.length;i++){const c=source[i];if(c==='\\'&&i+1<source.length){value+=source[++i];continue;}if(c==='_'){flush();underline=!underline;continue;}if(c==='*'){flush();if(source[i+1]==='*'){bold=!bold;i++;}else italic=!italic;continue;}value+=c;}flush();return runs;}
export function parseFountain(source){
 if(new TextEncoder().encode(source).length>32*1024*1024)throw Error('The script exceeds the 32 MB import limit.');
 const result=[],pairCues=[],scenes=[];let speech=false,shot=false,scene=0;
 for(const raw of source.replaceAll('\r\n','\n').split('\n')){const line=raw.trim();if(!line){speech=false;continue;}if(line==='/* DOT element: shot */'){shot=true;continue;}let element='action',content=line,number=null,dual=false;
  if(line.startsWith('.')||/^(INT\.|EXT\.|INT\.\/EXT\.|EXT\.\/INT\.|I\/E\.)\s/i.test(line)){element='slugline';scene++;speech=false;if(line.startsWith('.'))content=content.slice(1);const match=content.match(/\s+#([^#]+)#$/);if(match){number=match[1];content=content.slice(0,match.index);}}
  else if(line.startsWith('@')){element='character';content=content.slice(1);speech=true;if(content.endsWith(' ^')){content=content.slice(0,-2);dual=true;}}
  else if(line.startsWith('!')){element=shot?'shot':'action';content=content.slice(1);speech=false;shot=false;}
  else if(line.startsWith('>')){element='transition';content=content.slice(1).trim();speech=false;}
  else if(line.startsWith('~')){element='lyrics';content=content.slice(1);}
  else if(speech&&line.startsWith('('))element='parenthetical';
  else if(speech)element='dialogue';
  else if(line===line.toUpperCase()&&!line.includes('.')&&line.length<100){element='character';speech=true;if(content.endsWith(' ^')){content=content.slice(0,-2);dual=true;}}
  if(dual)pairCues.push(result.length);result.push({element,runs:fountainRuns(content),number,dualPair:null,dualSide:null});scenes.push(String(scene));
 }
 for(const cue of pairCues){const plan=dualPairPlan(result.map((p,i)=>({element:p.element,text:text(p),scene:scenes[i]})),cue),id=crypto.randomUUID();for(const[range,side]of [[plan.left,'left'],[plan.right,'right']])for(let i=range[0];i<range[1];i++){if(result[i].dualPair)throw Error('Ambiguous Fountain dual dialogue.');result[i].dualPair=id;result[i].dualSide=side;}}
 return result;
}
