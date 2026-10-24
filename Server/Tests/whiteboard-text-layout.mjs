import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url)),publicDir=path.join(root,'Server/Public'),output=path.join(root,'build/parity');await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{if(req.url==='/'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/workspace-design.css"><link rel="stylesheet" href="/style.css"><link rel="stylesheet" href="/workspaces.css"><style>body{margin:0;color:white;font:12px system-ui}#timeline{height:700px!important}</style><div id="timeline"></div>');return;}const name=req.url.slice(1);if(name.includes('/')||name.includes('..'))throw Error();res.setHeader('Content-Type',name.endsWith('.js')?'application/javascript':'text/css');res.end(await readFile(path.join(publicDir,name)));}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:412,height:915},isMobile:true,deviceScaleFactor:2}),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:'+server.address().port);
 await page.evaluate(async()=>{
  await document.fonts.ready;
  const {beatSize}=await import('/board-operations.js');
  const titles=['Untitled Beat','Hhoogi','காகித கப்பல் கடலுல கவுந்துடுச்சா?', 'தமிழ் English கலந்த தலைப்பு 👨‍👩‍👧‍👦', 'கப்பல்'.repeat(30), 'First line\nஇரண்டாவது வரி\n', 'A long English title '.repeat(10)];
  window.results=[];
  for(const width of [80,140,212,360])for(const title of titles){
    const size=beatSize(title,width),card=document.createElement('div');card.className='beat';
    card.style.cssText=`width:${size.width}px;height:${size.height}px;background:purple;position:relative`;
    const label=document.createElement('div');label.className='beat-text';label.textContent=title;card.append(label);document.body.append(card);
    const bounds=card.getBoundingClientRect(),text=label.getBoundingClientRect();
    const range=document.createRange();range.selectNodeContents(label);
    const longest=Math.max(...[...range.getClientRects()].map(r=>r.width));
    if(size.width>32)results.push({title,width,size,contained:size.width-longest<=17,overflow:false});
    const panel=document.createElement('section');panel.style.width=width+'px';
    const heading=document.createElement('button');heading.className='script-beat-title';heading.textContent='▼ '+title;panel.append(heading);document.body.append(panel);
    results.push({title:'Script heading: '+title,width,size,contained:heading.getBoundingClientRect().width<=width,overflow:heading.scrollWidth>heading.clientWidth+1||heading.scrollHeight>heading.clientHeight+1});
    results.push({title,width,size,contained:text.bottom<=bounds.bottom-4&&text.right<=bounds.right,overflow:label.scrollHeight>label.clientHeight+1||label.scrollWidth>label.clientWidth+1});
  }
 });
 for(const result of await page.evaluate(()=>results)){assert.ok(result.contained,JSON.stringify(result));assert.equal(result.overflow,false,JSON.stringify(result));assert.ok(result.size.width<=result.width);}
 for(const zoom of [0.5,1,2]){await page.evaluate(zoom=>{document.body.style.transform=`scale(${zoom})`;document.body.style.transformOrigin='top left';},zoom);assert.equal(await page.locator('.beat:not(.beat-size-measure)').evaluateAll(nodes=>nodes.filter(n=>n.querySelector('.beat-text').getBoundingClientRect().bottom>n.getBoundingClientRect().bottom).length),0);}
 await page.setViewportSize({width:412,height:915});await page.evaluate(()=>document.body.style.transform='none');
 await page.screenshot({path:path.join(output,'browser-whiteboard-tamil-text.png'),fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: English, Tamil, mixed-script, emoji and multiline whiteboard text fits measured cards at multiple widths and zooms');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
