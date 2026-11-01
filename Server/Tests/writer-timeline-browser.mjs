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
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.locator('#import-project').setInputFiles({name:'Timeline.dot',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 const mini=page.getByRole('region',{name:'Writer timeline'}),sheet=page.locator('.continuous-editor'),toggle=page.getByRole('button',{name:'Toggle Writer timeline',exact:true});
 assert.equal(await mini.isVisible(),false);
 await sheet.evaluate(n=>{window.retainedWriter=n;const p=n.querySelector('[data-beat-id="beat-1"]:not([data-heading-scene])');n.focus();const r=document.createRange();r.selectNodeContents(p);r.collapse(false);getSelection().removeAllRanges();getSelection().addRange(r);window.caretBefore={node:getSelection().anchorNode,offset:getSelection().anchorOffset};});
 await toggle.click();assert.ok(await mini.isVisible());assert.ok(await sheet.evaluate(n=>n===window.retainedWriter&&getSelection().anchorNode===window.caretBefore.node&&getSelection().anchorOffset===window.caretBefore.offset));
 await mini.getByLabel('Zoom timeline in',{exact:true}).click();const writerScale=await page.evaluate(()=>JSON.parse(localStorage.getItem('frontstage-timeline-writer')).scale);assert.equal(writerScale,75);
 const boardPrefs=await page.evaluate(()=>{const p=JSON.parse(localStorage.getItem('frontstage-timeline-mini'));delete p.time;delete p.lastSelected;return p;});
 await mini.locator('.timeline-item.beats[data-timeline-beat="beat-2"]').click();await page.waitForFunction(()=>document.querySelector('[data-writer-timeline] .timeline-item.beats[data-timeline-beat="beat-2"]').classList.contains('selected'));assert.ok(await sheet.evaluate(n=>n===window.retainedWriter));
 const body=sheet.locator('.sc-dialogue[data-beat-id="beat-2"]').first();await body.evaluate(n=>{n.closest('.continuous-editor').focus();const r=document.createRange();r.selectNodeContents(n);r.collapse(false);getSelection().removeAllRanges();getSelection().addRange(r);});await page.keyboard.type(' timeline typing');assert.ok((await body.textContent()).includes('timeline typing'),JSON.stringify(await sheet.evaluate(n=>({html:n.innerHTML,focus:document.activeElement?.outerHTML.slice(0,200),caret:getSelection()?.anchorNode?.parentElement?.outerHTML.slice(0,200)}))));assert.ok(await sheet.evaluate(n=>n===window.retainedWriter));
 await toggle.click();assert.equal(await mini.isVisible(),false);await toggle.click();assert.equal(await page.evaluate(()=>JSON.parse(localStorage.getItem('frontstage-timeline-writer')).scale),writerScale);assert.deepEqual(await page.evaluate(()=>{const p=JSON.parse(localStorage.getItem('frontstage-timeline-mini'));delete p.time;delete p.lastSelected;return p;}),boardPrefs);
 const popupEvent=page.waitForEvent('popup');await mini.getByRole('button',{name:'Detach Timeline',exact:true}).click();const popup=await popupEvent;await page.waitForFunction(()=>document.querySelector('[data-writer-timeline]').hidden);assert.ok(await sheet.evaluate(n=>n===window.retainedWriter));await popup.close();await page.waitForFunction(()=>!document.querySelector('[data-writer-timeline]').hidden);assert.ok(await sheet.evaluate(n=>n===window.retainedWriter));
 assert.deepEqual(errors,[]);console.log('PASS: Writer mini-timeline retains editor/caret, selects scenes, preserves independent zoom and docks without replacing screenplay');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
