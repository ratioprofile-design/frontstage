import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url));
const server=createServer(async(req,res)=>{try{const file=req.url==='/'?'index.html':decodeURIComponent(req.url.slice(1));if(file.includes('/')||file.includes('..'))throw Error();res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':'text/html');res.end(await readFile(path.join(root,'Server/Public',file)));}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(17845,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1440,height:850}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));
 fixture.project.frontstageWhiteboard.beats[0].html='<div><p class="sc-action">'+('A long screenplay paragraph. தமிழ் எழுத்து. '.repeat(350))+'</p><p class="sc-action"><br></p><p class="sc-dialogue">'+('A long dialogue paragraph. '.repeat(350))+'</p></div>';
 for(const scene of fixture.project.beats)scene.content=fixture.project.frontstageWhiteboard.beats.filter(b=>b.sceneID===scene.id).map(b=>b.html).join('');
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.waitForSelector('#projects:not([hidden])');await page.locator('#import-project').setInputFiles({name:'Writer scrolling.frontstage',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 const sheet=page.locator('.continuous-editor'),desk=page.locator('.continuous-desk');
 // Some caret positions return an empty rectangle in Chromium/WebKit. Exercise
 // that path consistently even on browser versions that measure those positions.
 await sheet.evaluate(n=>{window.originalCaretRect=Range.prototype.getBoundingClientRect;window.missingCaretRect=false;Range.prototype.getBoundingClientRect=function(){return this.collapsed&&window.missingCaretRect?new DOMRect():window.originalCaretRect.call(this);};window.writerUnderTest=n;});
 const sample=()=>sheet.evaluate(n=>{const s=getSelection(),range=s.getRangeAt(0),p=s.anchorNode.nodeType===3?s.anchorNode.parentElement:s.anchorNode,before=range.cloneRange();before.selectNodeContents(p);before.setEnd(s.anchorNode,s.anchorOffset);const rect=window.originalCaretRect.call(range);return {offset:before.toString().length,y:n.closest('.continuous-desk').scrollTop,outer:document.scrollingElement.scrollTop,top:rect.top,editor:n===window.writerUnderTest};});
 for(const zoom of [.8,1,1.4])for(const missing of [false,true]){
  await sheet.evaluate((n,zoom)=>n.style.zoom=zoom,zoom);
  for(const kind of ['action','dialogue']){
   const paragraph=sheet.locator('p.sc-'+kind).first();
   await paragraph.evaluate(n=>{n.closest('.continuous-editor').focus({preventScroll:true});const r=document.createRange();r.setStart(n.firstChild,Math.floor(n.firstChild.length/2));r.collapse(true);getSelection().removeAllRanges();getSelection().addRange(r);const rect=window.originalCaretRect.call(r),desk=n.closest('.continuous-desk');desk.scrollTop+=rect.top-desk.getBoundingClientRect().top-180;});
   await page.waitForTimeout(50);await page.evaluate(missing=>window.missingCaretRect=missing,missing);const initial=await sample();
   for(const character of ['a','b','c',' ']){await page.keyboard.insertText(character);await page.waitForTimeout(35);const now=await sample();assert.ok(Math.abs(now.y-initial.y)<3,JSON.stringify({kind,zoom,missing,initial,now}));assert.equal(now.outer,initial.outer);assert.equal(now.editor,true);}
   assert.equal((await sample()).offset,initial.offset+4,'Typing must preserve the logical caret');
  }
 }
 // Empty leaf lines inside imported wrappers must not use the wrapper's height.
 const empty=sheet.locator('p.sc-action').nth(1);await empty.evaluate(n=>{n.closest('.continuous-editor').focus({preventScroll:true});const r=document.createRange();r.setStart(n,0);r.collapse(true);getSelection().removeAllRanges();getSelection().addRange(r);const desk=n.closest('.continuous-desk');desk.scrollTop+=n.getBoundingClientRect().top-desk.getBoundingClientRect().top-180;});await page.waitForTimeout(50);const initial=await desk.evaluate(n=>n.scrollTop);await sheet.dispatchEvent('keyup',{key:'ArrowLeft'});await page.waitForTimeout(50);assert.ok(Math.abs(await desk.evaluate(n=>n.scrollTop)-initial)<3,'An empty imported line must stay in view');
 assert.deepEqual(errors,[]);console.log('PASS: stable Writer viewport and caret in multi-page/nested paragraphs, empty lines, missing caret rectangles, Tamil text and 80/100/140% paper zoom');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
