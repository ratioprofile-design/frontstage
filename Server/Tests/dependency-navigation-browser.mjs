import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const server=createServer(async(req,res)=>{try{const file=req.url==='/'?'index.html':decodeURIComponent(req.url.slice(1));if((file.includes('/')&&!file.startsWith('brand/'))||file.includes('..'))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.png')?'image/png':file.endsWith('.ico')?'image/x-icon':file.endsWith('.json')?'application/json':'text/html');res.end(await readFile(path.join(root,'Server/Public',file)));}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(17845,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1440,height:950}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));fixture.project.frontstageWhiteboard.blocks.forEach((b,i)=>{b.position={x:60+i*400,y:70+i*150};b.collapsed=false;});
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.locator('#import-project').setInputFiles({name:'Connections.dot',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');await page.locator('#blocks [data-beat-id="beat-2"]').waitFor();
 const download=async()=>{const event=page.waitForEvent('download');await page.locator('#download').evaluate(n=>n.click());return JSON.parse(await readFile(await (await event).path(),'utf8'));};
 const pathNode=()=>page.locator('#links [data-edge-id="cause-1"]');
 const openMenu=async()=>{const point=await pathNode().evaluate(n=>{const p=n.getPointAtLength(n.getTotalLength()/2),m=n.getScreenCTM();return {x:p.x*m.a+p.y*m.c+m.e,y:p.x*m.b+p.y*m.d+m.f};});await page.mouse.click(point.x,point.y,{button:'right'});await page.getByRole('menu',{name:'Whiteboard actions'}).waitFor();};
 const before=await download();await openMenu();assert.equal(await page.getByRole('menuitem',{name:/Go to Cause:/}).count(),1);
 await page.getByRole('menuitem',{name:/Go to Effect:/}).click();assert.ok(await page.locator('#blocks [data-beat-id="beat-2"]').evaluate(n=>n.classList.contains('selected')));assert.deepEqual((await download()).project.frontstageWhiteboard,before.project.frontstageWhiteboard);
 await openMenu();page.once('dialog',d=>d.accept('A clearer causal reason'));await page.getByRole('menuitem',{name:'Edit Connection Reason…',exact:true}).click();assert.equal((await download()).project.frontstageWhiteboard.dependencies[0].reason,'A clearer causal reason');
 await page.locator('#undo').click();assert.deepEqual((await download()).project.frontstageWhiteboard,before.project.frontstageWhiteboard);
 await openMenu();await page.getByRole('menuitem',{name:'Make Reference Connection',exact:true}).click();assert.equal((await download()).project.frontstageWhiteboard.dependencies[0].reference,true);await page.locator('#undo').click();
 await openMenu();await page.getByRole('menuitem',{name:'Remove Connection',exact:true}).click();assert.equal(await pathNode().count(),0);assert.equal((await download()).project.frontstageWhiteboard.dependencies.length,0);await page.locator('#undo').click();assert.equal(await pathNode().count(),1);await page.locator('#redo').click();assert.equal(await pathNode().count(),0);
 assert.deepEqual(errors,[]);console.log('PASS: right-click dependency navigation, reason/type changes, deletion and single-step undo/redo');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
