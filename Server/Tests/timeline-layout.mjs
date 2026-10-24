import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url)),publicDir=path.join(root,'Server/Public'),output=path.join(root,'build/parity');await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/workspace-design.css"><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/workspaces.css"><style>body{margin:0;color:white;font:12px system-ui}#timeline{height:700px!important}</style><div id="timeline"></div>');return;}const name=req.url.slice(1);if(name.includes('/')||name.includes('..'))throw Error();res.setHeader('Content-Type',name.endsWith('.js')?'application/javascript':'text/css');res.end(await readFile(path.join(publicDir,name)));}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:'+server.address().port);
 await page.evaluate(async()=>{
  const {timelineModel,timelinePreferences,mountTimeline}=await import('/story-timeline.js');
  const scenes=[{id:1,slug:{prefix:'INT.',location:'Hospital with a long readable location name',time:'DAY'}},{id:2,slug:{prefix:' int. ',location:' hospital with a long readable location name ',time:' day '}},{id:3,slug:{prefix:'EXT.',location:'Street',time:'DAY'}}];
  const board={layers:[{id:'main'}],blocks:[{id:'container',layerID:'main'}],beats:[1,2,3].map((n,i)=>({id:'beat-'+n,sceneID:n,blockID:'container',order:i,start:i,duration:1,title:i===1?'The nurse explains why the patient must wait for the family — மருத்துவமனையில் காத்திருக்கிறார்கள்':'Beat '+n,color:'#476b9c',html:'<p>Some screenplay.</p>',tags:[],characters:[]}))};
  const state={...timelinePreferences(true),expanded:true,time:0},actions={selected:null,render:()=>render(),choose:id=>{actions.selected=id;render();},open:()=>{},expand:()=>{},detach:()=>{},addMarker:()=>{},timing:()=>{},reorder:(ids,target)=>{window.dragged={ids,target};}};
  function render(){mountTimeline(document.getElementById('timeline'),timelineModel(board,scenes,[],state.timeBase),state,actions);}
  window.harness={board,scenes,state,render};render();
 });
 assert.equal(await page.locator('.timeline-item.scenes').count(),2);
 const scene=page.locator('.timeline-item.scenes').first();assert.equal(Math.round((await scene.boundingBox()).width),119);
 const firstBeat=page.locator('.timeline-item.beats').first(),longBeat=page.locator('.timeline-item.beats').nth(1);
 await longBeat.click();assert.ok((await scene.getAttribute('class')).includes('selected'));
 await page.getByLabel('Beat title lines',{exact:true}).selectOption('5');
 const limitedHeight=(await longBeat.boundingBox()).height;
 const text=longBeat.locator('.timeline-title-text');assert.ok((await text.evaluate(n=>n.scrollHeight))>(await text.evaluate(n=>n.clientHeight)));
 assert.equal(await text.evaluate(n=>n.clientHeight%16),0);
 await longBeat.focus();await page.getByRole('tooltip').waitFor();assert.ok((await page.getByRole('tooltip').innerText()).includes('மருத்துவமனையில்'));await page.keyboard.press('Escape');assert.equal(await page.getByRole('tooltip').count(),0);
 await page.mouse.move(1430,890);await page.keyboard.press('Escape');await page.screenshot({path:path.join(output,'browser-timeline-reference-titles.png')});
 const widths=await page.locator('.timeline-item.beats').evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().width));
 await page.getByLabel('Title Display',{exact:true}).selectOption('full');
 assert.ok((await longBeat.boundingBox()).height>limitedHeight);
 assert.equal(await page.locator('.timeline-item.title-full .timeline-title-text').evaluateAll(nodes=>nodes.filter(n=>n.scrollHeight>n.clientHeight+1||n.scrollWidth>n.clientWidth+1).length),0);
 assert.deepEqual(await page.locator('.timeline-item.beats').evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().width)),widths);
 assert.equal(await page.getByLabel('Beat title lines',{exact:true}).isDisabled(),true);
 await page.mouse.move(1430,890);await page.keyboard.press('Escape');
 await page.screenshot({path:path.join(output,'browser-timeline-full-titles.png')});
 for(const width of [900,1440]){await page.setViewportSize({width,height:900});for(const scale of [30,120]){await page.evaluate(scale=>{harness.state.scale=scale;harness.render();},scale);assert.equal(await page.locator('.timeline-item.title-full:not(.title-narrow) .timeline-title-text').evaluateAll(nodes=>nodes.filter(n=>n.scrollHeight>n.clientHeight+1||n.scrollWidth>n.clientWidth+1).length),0);}}
 await page.evaluate(()=>{harness.state.scale=2;harness.render();});assert.ok(await page.locator('.timeline-item.title-narrow').count()>0);await firstBeat.focus();assert.ok((await page.getByRole('tooltip').innerText()).includes('Beat 1'));
 await page.getByRole('button',{name:'Reset timeline zoom',exact:true}).click();await page.getByLabel('Title Display',{exact:true}).selectOption('reference');
 // Scene drag carries explicit membership across distinct source scene IDs.
 await scene.evaluate(node=>{const transfer=new DataTransfer();node.dispatchEvent(new DragEvent('dragstart',{bubbles:true,dataTransfer:transfer}));document.querySelectorAll('.timeline-item.beats')[2].dispatchEvent(new DragEvent('drop',{bubbles:true,cancelable:true,dataTransfer:transfer}));});
 assert.deepEqual(await page.evaluate(()=>window.dragged),{ids:['beat-1','beat-2'],target:'beat-3'});
 await page.locator('.story-track-label').filter({hasText:/^▾ Scenes$/}).click({button:'right'});await page.getByRole('menuitem',{name:'Full Titles',exact:true}).click();assert.equal(await page.getByLabel('Title Display',{exact:true}).inputValue(),'full');
 for(const base of ['time','pages']){await page.getByLabel('Primary time base',{exact:true}).selectOption(base);assert.equal(await page.locator('.timeline-item.scenes').count(),2);}
 assert.deepEqual(errors,[]);console.log('PASS: scene spans and drag membership, five-line truncation, full-title measurement, focus preview, zoom and compact widths');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
