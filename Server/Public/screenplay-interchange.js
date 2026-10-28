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
  const value=p.runs.map(run=>{let value=run.text;if(run.underline)value='_'+value+'_';if(run.italic)value='*'+value+'*';if(run.bold)value='**'+value+'**';return value;}).join('');
  if(p.element==='slugline')output.push('','.'+value+(p.number!=null?` #${p.number}#`:''),'');
  else if(p.element==='character')output.push('','@'+value+(p.dualSide==='right'?' ^':''));
  else if(p.element==='parenthetical')output.push((value.startsWith('(')?'':'(')+value+(value.endsWith(')')?'':')'));
  else if(p.element==='dialogue'){output.push(value);if(!['dialogue','parenthetical'].includes(paragraphs[index+1]?.element))output.push('');}
  else if(p.element==='transition')output.push('','> '+value,'');
  else if(p.element==='lyrics')output.push('~'+value);
  else output.push('','!'+value,'');
 }
 return output.join('\n').replace(/^\n+|\n+$/g,'')+'\n';
}
