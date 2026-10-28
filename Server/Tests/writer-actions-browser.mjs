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
 fixture.project.frontstageWhiteboard.beats[0].html='<p class="sc-line sc-action">Editable scene text.</p>';
 fixture.project.frontstageWhiteboard.beats[1].locked=true;
 fixture.project.frontstageWhiteboard.beats[1].html="<p class='sc-action'>Locked original scene.</p>";
 for(const scene of fixture.project.beats)scene.content=fixture.project.frontstageWhiteboard.beats.filter(b=>b.sceneID===scene.id).map(b=>b.html).join('');
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.waitForSelector('#projects:not([hidden])');
 await page.locator('#import-project').setInputFiles({name:'Writer typing.frontstage',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 const sheet=page.locator('.continuous-editor'),body=()=>sheet.locator('[data-beat-id="beat-1"]:not([data-heading-scene])');
 const active=()=>sheet.evaluate(()=>{let n=getSelection()?.anchorNode;if(n?.nodeType===3)n=n.parentElement;while(n&&n.parentElement&&!n.parentElement.classList.contains('continuous-editor'))n=n.parentElement;return {text:n?.textContent,kind:n?.className,caret:getSelection()?.anchorOffset};});
 try{await body().first().click();}catch(error){throw Error('Writer fixture did not open: '+JSON.stringify(await page.evaluate(()=>({status:document.querySelector('#status')?.textContent,page:document.querySelector('#workspace-page')?.textContent?.slice(0,500),mode:document.querySelector('#view-mode')?.value})))+' errors='+JSON.stringify(errors)+' '+error.message);}
 await body().first().evaluate(node=>{const r=document.createRange();r.setStart(node.firstChild,5);r.collapse(true);getSelection().removeAllRanges();getSelection().addRange(r);node.closest('[contenteditable]').focus();});
 await page.keyboard.type('X');assert.equal((await active()).text,'EditaXble scene text.');assert.equal((await active()).caret,6);
 await page.keyboard.type('YZ');assert.equal((await active()).text,'EditaXYZble scene text.');assert.equal((await active()).caret,8);
 await page.keyboard.press('Control+z');assert.equal(await body().first().textContent(),'Editable scene text.');
 await page.keyboard.press('Control+Shift+z');assert.equal(await body().first().textContent(),'EditaXYZble scene text.');
 await page.locator('#undo').click();assert.equal(await body().first().textContent(),'Editable scene text.');
 await page.locator('#redo').click();assert.equal(await body().first().textContent(),'EditaXYZble scene text.');
 // Card duplication creates a separate scene and is one reversible operation.
 await page.locator('.simple-beat-card[data-beat-id="beat-1"]').click({button:'right'});
 await page.getByRole('menuitem',{name:'Duplicate Beat',exact:true}).click();
 assert.equal(await page.locator('.simple-beat-card').count(),3);
 await page.locator('#undo').click();assert.equal(await page.locator('.simple-beat-card').count(),2);
 await page.locator('#redo').click();assert.equal(await page.locator('.simple-beat-card').count(),3);
 // The same operation is reachable from the script paper and whiteboard.
 await body().first().click({button:'right'});
 await page.getByRole('menuitem',{name:'Beat ›',exact:true}).click();
 await page.getByRole('menuitem',{name:'Duplicate Beat',exact:true}).click();
 assert.equal(await page.locator('.simple-beat-card').count(),4);
 await page.locator('#undo').click();assert.equal(await page.locator('.simple-beat-card').count(),3);
 await page.locator('#view-mode').selectOption('board');
 await page.locator('#blocks [data-beat-id="beat-1"]').click({button:'right'});
 await page.getByRole('menuitem',{name:'Duplicate Beat',exact:true}).click();
 await page.locator('#undo').click();
 await page.locator('#view-mode').selectOption('edit');
 assert.equal(await page.locator('.simple-beat-card').count(),3);
 await page.locator('#save').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Saved on this device'));
 const records=await page.evaluate(async()=>{const db=await new Promise(resolve=>{const r=indexedDB.open('frontstage-offline',1);r.onsuccess=()=>resolve(r.result);});return new Promise(resolve=>{const r=db.transaction('projects').objectStore('projects').getAll();r.onsuccess=()=>resolve(r.result);});});
 const saved=records.find(r=>r.doc?.name===fixture.name).doc.project.frontstageWhiteboard.beats;
 assert.equal(saved.find(b=>b.id==='beat-2').html,fixture.project.frontstageWhiteboard.beats[1].html,'Untouched locked HTML must not be serialized differently');
 const copy=saved.find(b=>!['beat-1','beat-2'].includes(b.id));assert.notEqual(copy.sceneID,saved.find(b=>b.id==='beat-1').sceneID);
 assert.deepEqual(errors,[]);console.log('PASS: locked-neighbor caret stability, typing history, button/shortcut undo and redo, independent card duplication and original HTML preservation');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
