export const timelineSections=[['episodes','Episodes'],['acts','Acts'],['chapters','Chapters'],['sections','Sections'],['scenes','Scenes'],['beats','Beats'],['tags','Tags / Emotions'],['characters','Characters'],['heat','Heat Map']];
export function timelinePreferences(expanded,stored=null){
  const result={timeBase:'beats',secondary:'time',scale:60,lines:2,colorStrength:.85,collapsed:new Set(),hidden:new Set(expanded?[]:['episodes','chapters','sections','tags','characters','heat'])};
  if(stored&&['beats','time','pages'].includes(stored.timeBase)&&['beats','time','pages'].includes(stored.secondary)&&stored.timeBase!==stored.secondary&&Number.isFinite(stored.scale)&&stored.scale>=2&&stored.scale<=180&&[1,2,3].includes(stored.lines)){
    Object.assign(result,{timeBase:stored.timeBase,secondary:stored.secondary,scale:stored.scale,lines:stored.lines,colorStrength:Number.isFinite(stored.colorStrength)?Math.max(0,Math.min(1,stored.colorStrength)):.85});
    for(const key of ['collapsed','hidden'])if(Array.isArray(stored[key]))result[key]=new Set(stored[key].filter(id=>timelineSections.some(([kind])=>id===kind)||(typeof id==='string'&&id.startsWith('group:'))));
  }return result;
}
export function timelineModel(board, scenes, markers = [], timeBase = 'beats', minutesPerPage = 1, trackGroups = {}) {
  minutesPerPage=Number.isFinite(minutesPerPage)&&minutesPerPage>=.1&&minutesPerPage<=10?minutesPerPage:1;
  const owners=new Map(board.blocks.map(b=>[b.id,b]));
  const unused=new Set(board.layers.filter(l=>l.unused).map(l=>l.id));
  const beats=board.beats.filter(b=>!b.omitted&&!unused.has(owners.get(b.blockID)?.layerID)).sort((a,b)=>a.order-b.order);
  let time=0,pages=0;const positions=new Map(),beatTimes={},beatPages={};
  beats.forEach((b,i)=>{const pageCount=Math.max(1/55,[...b.html.replace(/<[^>]*>/g,' ')].length/60/55),duration=b.timelineDuration??(pageCount*minutesPerPage);beatTimes[b.id]=time;beatPages[b.id]=pages;positions.set(b.id,{start:timeBase==='beats'?i:timeBase==='time'?time:pages,duration:timeBase==='beats'?1:timeBase==='time'?duration:pageCount});time+=duration;pages+=pageCount;});
  const item=b=>({id:b.id,title:b.title,...positions.get(b.id),color:b.color,beatID:b.id});
  const end=Math.max(timeBase==='beats'?25:1,...[...positions.values()].map(b=>b.start+b.duration+(timeBase==='beats'?2:.2)));
  const sceneItems=[];let lastScene=null;
  for(const beat of beats){const b={...beat,...positions.get(beat.id)};const last=sceneItems.at(-1);if(lastScene===b.sceneID&&last&&b.start<=last.start+last.duration+0.0001)last.duration=Math.max(last.duration,b.start+b.duration-last.start);else{const s=scenes.find(s=>s.id===b.sceneID);sceneItems.push({...item(b),id:'scene-'+b.id,title:s?`${s.slug?.location||s.title} – ${s.slug?.time||''}`:b.title});}lastScene=b.sceneID;}
  const tracks=[];
  for(const [kind,title]of [['episodes','Episodes'],['acts','Acts'],['chapters','Chapters'],['sections','Sections']]){
    const matching=markers.filter(m=>({episode:'episodes',chapter:'chapters',section:'sections'}[m.type]??'acts')===kind);
    const positions=matching.map(m=>positionsForMarker(m));
    tracks.push({id:kind,title,kind,items:matching.map((m,i)=>({id:m.id,title:m.title,start:positions[i],duration:Math.max(.1,(positions[i+1]??end)-positions[i]),color:'#476b9c',beatID:''}))});
  }
  function positionsForMarker(m){return positions.get(beats.find(b=>b.start>=m.unit)?.id)?.start??end;}
  tracks.push({id:'scenes',title:'Scenes',kind:'scenes',items:sceneItems},{id:'beats',title:'Beats',kind:'beats',items:beats.map(item)});
  for(const kind of ['tags','characters'])for(const name of [...new Set(beats.flatMap(b=>b[kind]))].sort())tracks.push({id:kind+':'+name,title:name,kind,group:typeof trackGroups[kind]?.[name]==='string'&&trackGroups[kind][name].trim()?trackGroups[kind][name]:(kind==='tags'?'General':'Main Characters'),items:beats.filter(b=>b[kind].includes(name)).map(b=>({...item(b),color:timelineColor(name)}))});
  for(const track of tracks.filter(t=>t.kind==='tags')){let value=0;const tracksEmotion=track.items.some(i=>beats.find(b=>b.id===i.id).emotionChanges?.[track.title]!=null);for(const item of track.items){const b=beats.find(b=>b.id===item.id);if(b.emotionChanges?.[track.title]!=null){item.absolute=(b.emotionAbsoluteTags??[]).includes(track.title);value=item.absolute?b.emotionChanges[track.title]:value+b.emotionChanges[track.title];item.tension=b.tensions?.[track.title]??0;}if(tracksEmotion)item.value=value;}}
  const heat=beats.flatMap(b=>{const tension=Object.entries(b.tensions||{}).filter(([tag])=>b.tags.includes(tag)).reduce((sum,[,v])=>sum+Math.max(0,v),0);return tension>0?[{...item(b),title:'Tension: '+tension,color:tension>=5?'#ffad25':'#93652c'}]:[];});
  tracks.push({id:'heat',title:'Heat Map · Tension',kind:'heat',items:heat});return {tracks,end,beats:beats.map(b=>({...b,sourceStart:b.start,...positions.get(b.id)})),beatTimes,beatPages,minutesPerPage};
}
export function timelineColor(name){const colors=['#11106b','#5de5bb','#a30e3f','#d6ae1c','#467e96'];return colors[[...name].reduce((sum,c)=>sum+c.codePointAt(0),0)%colors.length];}
export function timelineClock(time){const s=Math.max(0,Math.round(time*60));return [Math.floor(s/3600),Math.floor(s/60)%60,s%60].map(x=>String(x).padStart(2,'0')).join(':');}
export function mountTimeline(root,model,state,actions){
  const document=root.ownerDocument,view=document.defaultView;
  root._closeTimelineMenu?.();
  const menu=(event,entries)=>{
    event.preventDefault();event.stopPropagation();root._closeTimelineMenu?.();
    const popup=document.createElement('div');popup.className='board-context-menu timeline-context-menu';popup.setAttribute('role','menu');popup.setAttribute('aria-label','Timeline options');
    const close=()=>{popup.remove();document.removeEventListener('pointerdown',outside);document.removeEventListener('keydown',key);};
    const outside=e=>{if(!popup.contains(e.target))close();},key=e=>{if(e.key==='Escape'){close();root.focus();}};
    for(const [title,run,checked]of entries){const b=document.createElement('button');b.textContent=(checked?'✓ ':'')+title;b.setAttribute('role','menuitem');b.onclick=()=>{close();run();};popup.append(b);}
    document.body.append(popup);popup.style.left=Math.max(0,Math.min(event.clientX,view.innerWidth-popup.offsetWidth))+'px';popup.style.top=Math.max(0,Math.min(event.clientY,view.innerHeight-popup.offsetHeight))+'px';
    document.addEventListener('pointerdown',outside);document.addEventListener('keydown',key);root._closeTimelineMenu=close;popup.querySelector('button')?.focus();
  };
  const setBase=(key,value)=>{const old=state[key];state[key]=value;const other=key==='timeBase'?'secondary':'timeBase';if(state[other]===value)state[other]=old;state.lastSelected=null;actions.render();};
  const old=root.querySelector('.story-timeline-scroll'),scroll={x:old?.scrollLeft??0,y:old?.scrollTop??0};
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
  if(state.lastSelected!==actions.selected){const beat=model.beats.find(b=>b.id===actions.selected);if(beat)state.time=beat.start;state.lastSelected=actions.selected;}
  const scale=state.scale,width=model.end*scale,labelWidth=174;
  const toolbar=el('div',undefined,'story-timeline-tools');
  const readout=el('strong',undefined,'timeline-readout');readout.setAttribute('aria-live','polite');
  const primary=el('button',undefined,'timeline-counter'),secondary=el('button',undefined,'timeline-counter');readout.append(primary,secondary);
  for(const [node,key,label]of [[primary,'timeBase','Primary'],[secondary,'secondary','Secondary']]){node.setAttribute('aria-label',label+' timeline counter');node.oncontextmenu=e=>menu(e,[['Beat Number',()=>setBase(key,'beats'),state[key]==='beats'],['Time',()=>setBase(key,'time'),state[key]==='time'],['Pages',()=>setBase(key,'pages'),state[key]==='pages']]);}

  const refreshReadout=()=>{const index=model.beats.findIndex(b=>state.time>=b.start&&state.time<b.start+b.duration);const b=model.beats[index],fraction=b?Math.max(0,(state.time-b.start)/b.duration):0;const count=base=>base==='beats'?(index<0?'–':String(index+1)):base==='time'?timelineClock((model.beatTimes[b?.id]??0)+(b?.timelineDuration??(Math.max(1/55,[...(b?.html??'').replace(/<[^>]*>/g,' ')].length/60/55)*model.minutesPerPage))*fraction):((model.beatPages[b?.id]??0)+1+Math.max(1/55,[...(b?.html??'').replace(/<[^>]*>/g,' ')].length/60/55)*fraction).toFixed(2);primary.textContent=count(state.timeBase);secondary.textContent=count(state.secondary);primary.title=state.timeBase;secondary.title=state.secondary;};refreshReadout();toolbar.append(readout);
  const button=(title,fn)=>{const b=el('button',title);b.onclick=fn;toolbar.append(b);return b;};
  if(actions.detached)button('Dock Timeline',()=>actions.dock());else {button(state.expanded?'Restore Board':'Expand Timeline',()=>actions.expand(!state.expanded));button('Detach Timeline',()=>actions.detach());}
  const zoomTo=(value,anchor=null)=>{const scroller=root.querySelector('.story-timeline-scroll'),point=anchor??Math.max(0,(root.clientWidth-labelWidth)/2),unit=((scroller?.scrollLeft??0)+point)/state.scale;state.scale=Math.max(2,Math.min(180,value));actions.render();root.querySelector('.story-timeline-scroll').scrollLeft=Math.max(0,unit*state.scale-point);};
  button('−',()=>zoomTo(state.scale/1.25)).setAttribute('aria-label','Zoom timeline out');
  button(Math.round(state.scale/60*100)+'%',()=>zoomTo(60)).setAttribute('aria-label','Reset timeline zoom');
  button('+',()=>zoomTo(state.scale*1.25)).setAttribute('aria-label','Zoom timeline in');
  root.tabIndex=0;root.onwheel=e=>{if(e.target.closest('input,select,.story-timeline-tools')||e.shiftKey||Math.abs(e.deltaX)>Math.abs(e.deltaY))return;e.preventDefault();const frame=root.getBoundingClientRect();zoomTo(state.scale*Math.exp(-e.deltaY*.005),Math.max(0,e.clientX-frame.left-labelWidth));};
  root.onkeydown=e=>{if(['ArrowUp','ArrowDown'].includes(e.key)&&!['INPUT','SELECT','TEXTAREA','BUTTON'].includes(e.target.tagName)){e.preventDefault();zoomTo(state.scale*(e.key==='ArrowUp'?1.25:.8));return;}if(!(e.ctrlKey||e.metaKey)||['INPUT','SELECT','TEXTAREA'].includes(e.target.tagName))return;if(['+','=','-','0'].includes(e.key)){e.preventDefault();zoomTo(e.key==='0'?60:state.scale*(e.key==='-'?.8:1.25));}};
  button('Fit',()=>{state.scale=Math.max(2,(root.clientWidth-labelWidth-20)/model.end);actions.render();});
  for(const [key,label] of [['timeBase','Primary time base'],['secondary','Secondary time base']]){const select=el('select');select.setAttribute('aria-label',label);for(const [value,title]of [['beats','Beat Number'],['time','Time (estimated)'],['pages','Pages (estimated)']]){const option=el('option',title);option.value=value;select.append(option);}select.value=state[key];select.onchange=()=>{const old=state[key];state[key]=select.value;const other=key==='timeBase'?'secondary':'timeBase';if(state[other]===state[key])state[other]=old;state.lastSelected=null;actions.render();};toolbar.append(select);}
  const lines=el('select');lines.setAttribute('aria-label','Beat title lines');for(const n of [1,2,3]){const option=el('option',n+' title lines');option.value=n;lines.append(option);}lines.value=state.lines;lines.onchange=()=>{state.lines=Number(lines.value);actions.render();};toolbar.append(lines);
  const strength=el('input');strength.type='range';strength.min='0';strength.max='1';strength.step='.05';strength.value=state.colorStrength??.85;strength.setAttribute('aria-label','Beat color strength');strength.title='Beat color strength';strength.onchange=()=>{state.colorStrength=Number(strength.value);actions.render();};toolbar.append(strength);
  const trackOptions=()=>timelineSections.map(([kind,title])=>[title,()=>{state.hidden.has(kind)?state.hidden.delete(kind):state.hidden.add(kind);actions.render();},!state.hidden.has(kind)]);
  const tracksMenu=el('details',undefined,'timeline-track-menu'),summary=el('summary','Tracks');tracksMenu.append(summary);
  for(const [kind,title] of timelineSections){const label=el('label'),check=el('input');check.type='checkbox';check.checked=!state.hidden.has(kind);check.setAttribute('aria-label','Show '+title+' track');check.onchange=()=>{check.checked?state.hidden.delete(kind):state.hidden.add(kind);actions.render();};label.append(check,document.createTextNode(title));tracksMenu.append(label);}toolbar.append(tracksMenu);
  const add=el('select');add.setAttribute('aria-label','Add structural break');add.append(el('option','Add Break…'));for(const type of ['episode','act','chapter','section']){const option=el('option',type[0].toUpperCase()+type.slice(1));option.value=type;add.append(option);}add.onchange=()=>{actions.addMarker(add.value);add.selectedIndex=0;};toolbar.append(add);
  button('Timing…',()=>actions.timing());
  const scroller=el('div',undefined,'story-timeline-scroll'),grid=el('div',undefined,'story-timeline-grid');grid.style.width=(width+labelWidth)+'px';
  const row=(title,height=28)=>{const r=el('div',undefined,'story-timeline-row');r.style.height=height+'px';const label=el('div',title,'story-track-label'),body=el('div',undefined,'story-track-body');body.style.width=width+'px';body.style.backgroundSize=(scale*5)+'px 100%';label.oncontextmenu=e=>menu(e,trackOptions());r.append(label,body);grid.append(r);return {r,label,body};};
  const ruler=row('Story Time',36);ruler.body.classList.add('story-ruler');ruler.body.tabIndex=0;ruler.body.setAttribute('role','slider');ruler.body.setAttribute('aria-label','Timeline playhead');ruler.body.setAttribute('aria-valuemin','0');ruler.body.setAttribute('aria-valuemax',String(model.end));ruler.body.setAttribute('aria-valuenow',String(state.time));
  const tick=Math.max(1,Math.ceil(55/scale));for(let t=0;t<=model.end;t+=tick){const mark=el('span',String(t),'story-tick');mark.style.left=t*scale+'px';ruler.body.append(mark);}
  const choose=item=>{if(!item.beatID)return;state.time=item.start;state.lastSelected=item.beatID;actions.choose(item.beatID);};
  for(const [kind,sectionTitle] of timelineSections){
    if(state.hidden.has(kind))continue;
    const structural=['episodes','acts','chapters','sections'].includes(kind);
    const flat=structural||['scenes','beats','heat'].includes(kind);
    if(!flat){const section=row('',26);const toggle=el('button',`${state.collapsed.has(kind)?'▸':'▾'} ${sectionTitle}`);toggle.setAttribute('aria-expanded',String(!state.collapsed.has(kind)));toggle.onclick=()=>{state.collapsed.has(kind)?state.collapsed.delete(kind):state.collapsed.add(kind);actions.render();};section.label.append(toggle);if(state.collapsed.has(kind))continue;const tracks=model.tracks.filter(t=>t.kind===kind);if(!tracks.length)section.body.append(el('span',`No ${kind} data yet.`,'timeline-empty'));}
    const sectionTracks=model.tracks.filter(t=>t.kind===kind).sort((a,b)=>(a.group??'').localeCompare(b.group??'') || Number(b.items.some(i=>i.value!=null))-Number(a.items.some(i=>i.value!=null)) || a.title.localeCompare(b.title));
    let previousGroup=null,previousEmotion=null;
    for(const track of sectionTracks){
      if(track.group){const groupKey='group:'+kind+':'+track.group;
        if(previousGroup!==track.group){const groupRow=row('',26),toggle=el('button',`${state.collapsed.has(groupKey)?'▸':'▾'} ${kind==='characters'?'📁 ':''}${track.group}`);toggle.setAttribute('aria-label','Toggle '+track.group+' '+kind);toggle.setAttribute('aria-expanded',String(!state.collapsed.has(groupKey)));toggle.onclick=()=>{state.collapsed.has(groupKey)?state.collapsed.delete(groupKey):state.collapsed.add(groupKey);actions.render();};groupRow.label.append(toggle);previousGroup=track.group;previousEmotion=null;}
        if(state.collapsed.has(groupKey))continue;
        const isEmotion=track.items.some(i=>i.value!=null);if(kind==='tags'&&previousEmotion!==isEmotion){row(isEmotion?'Emotions':'Tags',20);previousEmotion=isEmotion;}
      }
      const emotional=kind==='tags'&&track.items.some(i=>i.value!=null),height=flat&&state.collapsed.has(kind)?26:kind==='beats'?state.lines*15+10:emotional?72:28;const {body,label}=row(flat?'':track.title,height);
      if(flat){const toggle=el('button',`${state.collapsed.has(kind)?'▸':'▾'} ${sectionTitle}`);toggle.setAttribute('aria-expanded',String(!state.collapsed.has(kind)));toggle.onclick=()=>{state.collapsed.has(kind)?state.collapsed.delete(kind):state.collapsed.add(kind);actions.render();};label.append(toggle);}
      if(['tags','characters'].includes(kind))label.oncontextmenu=e=>menu(e,[[kind==='tags'?'Set Tag Category…':'Set Character Group…',()=>actions.group(kind,track.title,track.group)],...trackOptions()]);
      if(kind==='beats')label.oncontextmenu=e=>menu(e,[...[1,2,3].map(n=>[n+' title lines',()=>{state.lines=n;actions.render();},state.lines===n]),...[0,.35,.65,1].map(n=>['Color strength '+Math.round(n*100)+'%',()=>{state.colorStrength=n;actions.render();}]),...trackOptions()]);
      if(flat&&state.collapsed.has(kind))continue;
      if(kind==='tags'&&track.items.length>1){const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('width',width);svg.setAttribute('height',height);svg.classList.add('timeline-curve');const path=document.createElementNS(svg.namespaceURI,'polyline');path.setAttribute('points',track.items.map(i=>`${(i.start+i.duration/2)*scale},${emotional?height-6-Math.max(0,Math.min(100,i.value??0))/100*(height-12):height/2}`).join(' '));path.setAttribute('fill','none');path.setAttribute('stroke',track.items[0].color);path.setAttribute('stroke-width','2');svg.append(path);body.append(svg);}
      for(const item of track.items){const node=el(item.beatID||structural?'button':'div',(structural||['beats','scenes'].includes(kind))?item.title:undefined,'timeline-item '+kind);node.title=item.title;node.setAttribute('aria-label',`${track.title}: ${item.title}`);node.dataset.timelineBeat=item.beatID;node.style.left=item.start*scale+'px';node.style.width=Math.max(3,item.duration*scale-1)+'px';node.style.setProperty('--track-color',item.color);if(['beats','scenes'].includes(kind))node.style.background=`color-mix(in srgb, ${item.color} ${Math.round((state.colorStrength??.85)*100)}%, #333)`;if(item.beatID===actions.selected)node.classList.add('selected');if(['characters','tags'].includes(kind)){const dot=el('i');if(emotional)dot.style.top=(height-6-Math.max(0,Math.min(100,item.value??0))/100*(height-12))+'px';if(item.absolute)dot.style.borderRadius='0';if(item.value<0||item.value>100)dot.style.outline='2px solid white';if(item.tension>0)dot.style.boxShadow=`0 0 ${item.tension*3}px 3px ${item.color}`;node.append(dot);}if(structural||['beats','scenes'].includes(kind)){node.draggable=true;node.ondragstart=e=>{const ids=kind==='scenes'?model.beats.filter(b=>b.start>=item.start&&b.start<item.start+item.duration).map(b=>b.id):[item.beatID];e.dataTransfer.setData('text/frontstage-timeline',JSON.stringify({ids,marker:structural?item.id:null}));};node.ondragover=e=>e.preventDefault();node.ondrop=e=>{e.preventDefault();e.stopPropagation();try{const data=JSON.parse(e.dataTransfer.getData('text/frontstage-timeline'));if(data.marker)actions.moveMarker(data.marker,model.beats.find(b=>b.id===item.beatID)?.sourceStart??item.start);else if(item.beatID)actions.reorder(data.ids,item.beatID);}catch{}};}
      node.onclick=()=>structural?actions.marker(item.id):choose(item);node.oncontextmenu=e=>{e.preventDefault();if(structural)actions.markerType(item.id);else if(kind==='tags')actions.emotion(item.beatID,track.title);else if(kind==='beats')actions.duration(item.beatID);};node.ondblclick=()=>{if(item.beatID)actions.open(item.beatID);};body.append(node);}
    }
  }
  const line=el('div',undefined,'timeline-playhead');line.style.left=(labelWidth+state.time*scale)+'px';grid.append(line);
  const scrub=value=>{state.time=Math.max(0,Math.min(model.end,value));line.style.left=(labelWidth+state.time*scale)+'px';refreshReadout();ruler.body.setAttribute('aria-valuenow',String(state.time));};
  const selectAtCursor=()=>{const beat=model.beats.find(b=>state.time>=b.start&&state.time<b.start+b.duration);if(beat){state.lastSelected=beat.id;actions.choose(beat.id);}};
  ruler.body.onpointerdown=e=>{e.preventDefault();ruler.body.setPointerCapture(e.pointerId);const move=e=>scrub((e.clientX-ruler.body.getBoundingClientRect().left)/scale);move(e);ruler.body.onpointermove=move;ruler.body.onpointerup=()=>{ruler.body.onpointermove=null;selectAtCursor();};ruler.body.onpointercancel=()=>ruler.body.onpointermove=null;};
  ruler.body.onkeydown=e=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();scrub(e.key==='Home'?0:e.key==='End'?model.end:state.time+(e.key==='ArrowLeft'?-.1:.1));selectAtCursor();}};
  scroller.append(grid);root.replaceChildren(toolbar,scroller);root.classList.add('story-timeline');root.classList.toggle('expanded',state.expanded);scroller.scrollLeft=scroll.x;scroller.scrollTop=scroll.y;
}
