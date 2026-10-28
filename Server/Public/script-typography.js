export const scriptElements=['slugline','action','character','dialogue','parenthetical','transition','shot','lyrics'];
export function validateTypography(value){
 if(!value||typeof value.fontName!=='string'||!value.fontName.trim()||value.fontName.length>120||!Number.isFinite(value.fontSize)||value.fontSize<8||value.fontSize>36||!Number.isFinite(value.lineHeight)||value.lineHeight<value.fontSize||value.lineHeight>60||!Number.isFinite(value.paragraphSpacing)||value.paragraphSpacing<0||value.paragraphSpacing>48)throw Error('Choose valid screenplay typography.');
 if(value.elements!=null&&(typeof value.elements!=='object'||Array.isArray(value.elements)))throw Error('Invalid element typography.');
 for(const entry of Object.values(value.elements||{})){
  if(!entry||typeof entry!=='object'||Array.isArray(entry))throw Error('Invalid element typography.');
  if(entry.fontName!=null&&(typeof entry.fontName!=='string'||entry.fontName.length>120))throw Error('Invalid element font.');
  if(entry.fontSize!=null&&(!Number.isFinite(entry.fontSize)||entry.fontSize<8||entry.fontSize>36))throw Error('Choose an element size from 8 to 36.');
  for(const key of ['isBold','isItalic','isUnderline','isUppercase','isTamil'])if(entry[key]!=null&&typeof entry[key]!=='boolean')throw Error('Invalid typography flag.');
 }
 return value;
}
export function setTypography(document,value){
 validateTypography(value);const prior=document.project.frontstageScriptLayout||{},elements={...prior.elements},inactive={...prior.frontstageInactiveElementTypography},known=new Set(['fontName','fontSize','isBold','isItalic','isUnderline','isUppercase','isTamil']);
 for(const key of scriptElements)if(!Object.hasOwn(value.elements||{},key)){if(elements[key]&&Object.keys(elements[key]).some(k=>!known.has(k)))inactive[key]=structuredClone(elements[key]);delete elements[key];}
 for(const[key,entry]of Object.entries(value.elements||{})){const extensions=Object.fromEntries(Object.entries(inactive[key]||{}).filter(([k])=>!known.has(k)));elements[key]={...(elements[key]||extensions),...entry};delete inactive[key];}
 const next={...prior,...structuredClone(value),elements};if(Object.keys(inactive).length)next.frontstageInactiveElementTypography=inactive;else delete next.frontstageInactiveElementTypography;document.project.frontstageScriptLayout=next;
}
export function applyTypography(node,t={}){
 node.style.setProperty('--script-font',JSON.stringify(t.fontName||'Courier'));
 node.style.setProperty('--script-size',`${t.fontSize||12}px`);node.style.setProperty('--script-line',`${t.lineHeight||14}px`);node.style.setProperty('--script-spacing',`${t.paragraphSpacing??10}px`);
 // Inherited variables format existing and newly typed paragraphs without replacing editor nodes.
 for(const element of scriptElements){const entry=t.elements?.[element];for(const key of ['font','size','weight','style','decoration','case','line'])node.style.removeProperty(`--script-${element}-${key}`);if(!entry)continue;
  node.style.setProperty(`--script-${element}-font`,JSON.stringify(entry.fontName||t.fontName||'Courier'));
  node.style.setProperty(`--script-${element}-size`,`${entry.fontSize||t.fontSize||12}px`);
  node.style.setProperty(`--script-${element}-line`,`${Math.max((entry.fontSize||t.fontSize||12)*(entry.isTamil?1.45:1),t.lineHeight||14)}px`);
  for(const[key,value]of Object.entries({weight:entry.isBold?'bold':'normal',style:entry.isItalic?'italic':'normal',decoration:entry.isUnderline?'underline':'none',case:entry.isUppercase?'uppercase':'none'}))node.style.setProperty(`--script-${element}-${key}`,value);
 }
}

export function popupTypography(settings={}){const t={fontName:'Courier',fontSize:12,lineHeight:14,paragraphSpacing:10,...structuredClone(settings)},scale=Math.max(1,15/t.fontSize);t.fontSize*=scale;t.lineHeight*=scale;t.paragraphSpacing*=scale;for(const entry of Object.values(t.elements||{}))if(entry.fontSize)entry.fontSize=Math.max(15,entry.fontSize*scale);return t;}

export function fontAvailable(name){
 if(!name||['serif','sans-serif','monospace','system-ui'].includes(name.toLowerCase()))return true;
 const context=document.createElement('canvas').getContext('2d');if(!context)return true;
 const sample='DOT mmwwii 012345 தமிழ்';
 return ['monospace','serif','sans-serif'].some(fallback=>{context.font=`72px ${fallback}`;const baseline=context.measureText(sample).width;context.font=`72px ${JSON.stringify(name)},${fallback}`;return Math.abs(context.measureText(sample).width-baseline)>.01;});
}
