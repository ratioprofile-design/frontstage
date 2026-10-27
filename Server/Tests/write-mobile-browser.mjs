import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium,devices}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const server=createServer(async(req,res)=>{try{const file=req.url==='/'?'index.html':decodeURIComponent(req.url.slice(1));if(file.includes('/')||file.includes('..'))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(await readFile(path.join(root,'Server/Public',file)));}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(17845,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({...devices['Pixel 7'],viewport:{width:1440,height:950}}),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').tap();await page.locator('#back').tap();await page.waitForSelector('#projects:not([hidden])');await page.locator('#import-project').setInputFiles(path.join(root,'Tests/Fixtures/write-panels.frontstage'));await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 await page.setViewportSize({width:393,height:851});
 const paper=page.locator('.continuous-editor'),inspector=page.locator('.write-right'),scenes=page.locator('.write-left'),opener=page.getByRole('button',{name:'Notes / Breakdown / History',exact:true}),close=inspector.getByRole('button',{name:'Close inspector',exact:true});
 await paper.evaluate(n=>{window.mobilePaper=n;window.mobileZoom=n.style.zoom;const p=n.querySelector('[data-beat-id]:not([data-heading-scene])'),r=document.createRange();r.selectNodeContents(p);r.collapse(false);getSelection().removeAllRanges();getSelection().addRange(r);});
 assert.equal(await inspector.isVisible(),false);await opener.tap();assert.equal(await inspector.getAttribute('aria-modal'),'true');assert.ok(await close.isVisible());assert.ok(await paper.evaluate(n=>n.inert||n.closest('.write-center').inert));
 await inspector.getByLabel('Note scope',{exact:true}).selectOption('Both');assert.equal(await inspector.locator('[data-note-scope]').count(),2);
 const sceneNotes=inspector.locator('[data-note-scope="Scene"]');await sceneNotes.getByRole('button',{name:'Add Note',exact:true}).tap();const note=sceneNotes.getByRole('textbox',{name:'Note text',exact:true}).last();await note.fill('தமிழ் mobile note '.repeat(50));
 const noteNode=await note.elementHandle();await note.evaluate(n=>n.closest('[data-note-scope]').scrollTop=10000);const before=await close.boundingBox();assert.ok(before.y>=0&&before.y+before.height<=851);
 await close.tap();assert.equal(await inspector.isVisible(),false);assert.equal(await opener.getAttribute('aria-expanded'),'false');assert.ok(await paper.evaluate(n=>n===window.mobilePaper&&n.style.zoom===window.mobileZoom));
 await opener.tap();assert.ok(await note.evaluate((n,old)=>n===old,noteNode));assert.ok((await note.innerText()).startsWith('தமிழ் mobile note'));
 // A swipe on panel content must not dismiss it; swipes belong to the header.
 const client=await context.newCDPSession(page);
 async function swipe(x,y,dx,dy){await client.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});for(let i=1;i<=8;i++){await page.waitForTimeout(20);await client.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x:x+dx*i/8,y:y+dy*i/8}]});}await client.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await page.waitForTimeout(200);}
 const content=await inspector.locator('.write-panel-body').boundingBox();await swipe(content.x+50,content.y+150,0,-80);assert.ok(await inspector.isVisible());assert.ok(await close.isVisible());
 const header=await inspector.locator('.write-drawer-header').boundingBox();await swipe(header.x+50,header.y+25,105,2);assert.equal(await inspector.isVisible(),false);
 await opener.tap();assert.ok(await inspector.isVisible(),'Inspector reopens after swipe dismissal');await page.locator('.write-drawer-backdrop').tap({position:{x:12,y:90}});assert.equal(await inspector.isVisible(),false);
 await page.locator('#scenes-toggle').tap();assert.ok(await scenes.getByRole('button',{name:'Close scenes panel',exact:true}).isVisible());const leftHeader=await scenes.locator('.write-drawer-header').boundingBox();await swipe(leftHeader.x+140,leftHeader.y+25,-100,2);assert.equal(await scenes.isVisible(),false);
 await opener.tap();await close.focus();await page.keyboard.press('Shift+Tab');assert.ok(await inspector.evaluate(n=>n.contains(document.activeElement)));await page.keyboard.press('Tab');assert.ok(await close.evaluate(n=>n===document.activeElement));await page.keyboard.press('Escape');assert.equal(await inspector.isVisible(),false);
 // Simulate a reduced visual viewport without changing layout width, as with Android's keyboard.
 await opener.tap();await page.evaluate(()=>{Object.defineProperty(window.visualViewport,'height',{configurable:true,value:350});window.visualViewport.dispatchEvent(new Event('resize'));});
 let bounds=await close.boundingBox();assert.ok(bounds.y>=0&&bounds.y+bounds.height<=350);await close.tap();
 await page.evaluate(()=>{delete window.visualViewport.height;window.visualViewport.dispatchEvent(new Event('resize'));});
 await page.setViewportSize({width:851,height:393});await opener.tap();bounds=await close.boundingBox();assert.ok(bounds.y>=0&&bounds.y+bounds.height<=393);await close.tap();
 await page.setViewportSize({width:1440,height:950});assert.equal(await close.isVisible(),false);assert.equal(await inspector.getAttribute('aria-modal'),null);assert.equal(await page.locator('.write-drawer-backdrop').isVisible(),false);assert.ok(await paper.evaluate(n=>!n.closest('.write-center').inert&&n===window.mobilePaper));
 await page.setViewportSize({width:393,height:851});await opener.tap();await mkdir(path.join(root,'build/parity'),{recursive:true});await page.screenshot({path:path.join(root,'build/parity/write-mobile-inspector.png')});
 await close.tap();await page.locator('#view-mode').selectOption('board');assert.equal(await page.locator('#scenes-toggle').getAttribute('aria-controls'),null);assert.deepEqual(errors,[]);
 console.log('PASS: Android Write drawers, persistent close controls, both note scopes, touch swipe/outside/Escape dismissal, retained editors, keyboard viewport, rotation, desktop and listener cleanup');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
