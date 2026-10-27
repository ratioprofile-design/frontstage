export const filterKinds=['Beats','Tags','Characters','Locations','Blocks','Lanes'];
export const filterDefaults=()=>({facets:{},query:'',hideDisabled:false,hideEmpty:false,hideHeadings:false,hideBreaks:false,hideGaps:false,gaps:'Pages'});
const plain=html=>String(html||'').replace(/<[^>]*>/g,' ').replace(/&nbsp;/gi,' ').trim();
const characters=beat=>[...(beat.characters||[]),...[...String(beat.html||'').matchAll(/<(?:p|div)[^>]*class=["'][^"']*sc-character[^"']*["'][^>]*>([\s\S]*?)<\/(?:p|div)>/gi)].map(m=>plain(m[1]).replace(/\s*\([^)]*\)\s*$/,''))];
const key=value=>String(value).normalize('NFC').toUpperCase();
export function beatFilterValues(beat,board,scenes){
 const block=board.blocks.find(b=>b.id===beat.blockID),scene=scenes.find(s=>s.id===beat.sceneID),ancestors=[];let owner=block;const seen=new Set();while(owner&&!seen.has(owner.id)){seen.add(owner.id);ancestors.push(owner.id);owner=board.blocks.find(b=>b.id===owner.parentID);}
 return {Beats:[beat.id],Tags:beat.tags||[],Characters:characters(beat),Locations:[scene?.slug?.location||'UNTITLED SCENE'],Blocks:ancestors,Lanes:[block?.layerID||'']};
}
export function matchesScriptFilter(beat,board,scenes,state){
 const values=beatFilterValues(beat,board,scenes),scene=scenes.find(s=>s.id===beat.sceneID);
 if(state.hideDisabled&&(beat.omitted||scene?.isDisabled))return false;
 if(state.hideEmpty&&!plain(beat.html))return false;
 if(state.query&&![beat.title,beat.synopsis,plain(beat.html),...values.Tags,...values.Characters].join(' ').toLowerCase().includes(state.query.toLowerCase()))return false;
 return Object.entries(state.facets).every(([kind,facet])=>{if(!facet.values.length)return true;const own=(values[kind]||[]).map(key),checks=facet.values.map(v=>own.includes(key(v))),match=facet.all?checks.every(Boolean):checks.some(Boolean);return facet.hide?!match:match;});
}
export function filterChoices(kind,board,scenes){
 if(kind==='Beats')return board.beats.map(b=>[b.id,b.title]);
 if(kind==='Blocks')return board.blocks.filter(b=>!b.standalone).map(b=>[b.id,b.name]);
 if(kind==='Lanes')return board.layers.map(b=>[b.id,b.name]);
 const values=kind==='Locations'?scenes.map(s=>s.slug?.location||'UNTITLED SCENE'):board.beats.flatMap(b=>kind==='Tags'?b.tags||[]:characters(b));
 return [...new Map(values.map(v=>[key(v),[v,v]])).values()].sort((a,b)=>a[1].localeCompare(b[1]));
}
export function gapLabel(beats,mode){if(mode==='Time')return `${beats.reduce((n,b)=>n+(b.duration||0),0).toFixed(1)} seconds omitted`;if(mode==='Pages')return `≈ ${(beats.reduce((n,b)=>n+plain(b.html).length,0)/1800).toFixed(1)} pages omitted`;return `${beats.length} beats omitted`;}
export function createScriptFilter(){
 let state=filterDefaults(),past=[],future=[];
 return {get state(){return state;},clear(){state=filterDefaults();past=[];future=[];},get canBack(){return !!past.length;},get canForward(){return !!future.length;},set(next){past.push(structuredClone(state));if(past.length>100)past.shift();state=structuredClone(next);future=[];},back(){if(past.length){future.push(state);state=past.pop();}},forward(){if(future.length){past.push(state);state=future.pop();}},reset(){this.set(filterDefaults());}};
}
export function mountScriptFilter(root,controller,{board,scenes,selection,changed}){
 const render=()=>{const open=new Set([...root.querySelectorAll('details[open]>summary')].map(n=>n.textContent));root.replaceChildren();const state=controller.state;
 const button=(name,run,disabled=false)=>{const b=document.createElement('button');b.textContent=name;b.disabled=disabled;b.onclick=()=>{run();changed();render();};root.append(b);return b;};
 const update=fn=>{const next=structuredClone(controller.state);fn(next);controller.set(next);};
 button('Filter On Selection',()=>update(s=>{s.facets.Beats={values:[...selection()],hide:false,all:false};}),!selection().size);
 button('Go Back',()=>controller.back(),!controller.canBack);button('Go Forward',()=>controller.forward(),!controller.canForward);button('Reset Filter',()=>controller.reset());
 const search=document.createElement('input');search.placeholder='Search script';search.setAttribute('aria-label','Filter script');search.value=state.query;search.onchange=()=>{update(s=>s.query=search.value);changed();render();};root.append(search);
 const title=document.createElement('strong');title.textContent='Filter By';root.append(title);
 for(const kind of filterKinds){const details=document.createElement('details'),summary=document.createElement('summary');summary.textContent=kind+'…';details.append(summary);details.open=open.has(kind+'…');root.append(details);const facet=state.facets[kind]||{values:[],hide:false,all:false};
 const mode=document.createElement('select');mode.setAttribute('aria-label',kind+' show or hide');mode.append(new Option('Show selected','show'),new Option('Hide selected','hide'));mode.value=facet.hide?'hide':'show';mode.onchange=()=>{update(s=>s.facets[kind]={...(s.facets[kind]||facet),hide:mode.value==='hide'});changed();render();};details.append(mode);
 if(['Tags','Characters'].includes(kind)){const match=document.createElement('select');match.setAttribute('aria-label',kind+' match');match.append(new Option('Any (OR)','any'),new Option('All (AND)','all'));match.value=facet.all?'all':'any';match.onchange=()=>{update(s=>s.facets[kind]={...(s.facets[kind]||facet),all:match.value==='all'});changed();render();};details.append(match);}
 for(const [id,name]of filterChoices(kind,board(),scenes())){const label=document.createElement('label'),check=document.createElement('input');check.type='checkbox';check.checked=facet.values.includes(id);check.setAttribute('aria-label',kind+': '+name);check.onchange=()=>{update(s=>{const current=s.facets[kind]||structuredClone(facet);current.values=check.checked?[...new Set([...current.values,id])]:current.values.filter(v=>v!==id);s.facets[kind]=current;});changed();render();};label.append(check,document.createTextNode(name));details.append(label);}
 }
 const gaps=document.createElement('select');gaps.setAttribute('aria-label','Filter gap units');for(const mode of ['Time','Pages','Events'])gaps.append(new Option(mode,mode));gaps.value=state.gaps;gaps.onchange=()=>{update(s=>s.gaps=gaps.value);changed();render();};root.append(gaps);
 const always=document.createElement('strong');always.textContent='Always-On Filters';root.append(always);
 for(const [name,key]of [['Hide Disabled Beats','hideDisabled'],['Hide Empty Beats','hideEmpty'],['Hide Scene Headings','hideHeadings'],['Hide Breaks','hideBreaks'],['Hide Filter Gaps','hideGaps']]){const label=document.createElement('label'),check=document.createElement('input');check.type='checkbox';check.checked=state[key];check.onchange=()=>{update(s=>s[key]=check.checked);changed();render();};label.append(check,document.createTextNode(name));root.append(label);}
 };render();root.parentElement.addEventListener('toggle',()=>{if(root.parentElement.open&&!root.contains(document.activeElement))render();});
}
