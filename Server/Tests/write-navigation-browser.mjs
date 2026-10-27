import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir} from 'node:fs/promises';
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
 const page=await browser.newPage({viewport:{width:1440,height:950}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));
 for(const beat of fixture.project.frontstageWhiteboard.beats)beat.html='<p class="sc-line sc-action">Long screenplay scrolling paragraph. தமிழ்.</p>'.repeat(100);
 const repeat=structuredClone(fixture.project.frontstageWhiteboard.beats[0]);repeat.id='repeat';repeat.order=10;fixture.project.frontstageWhiteboard.beats.push(repeat);
 for(const scene of fixture.project.beats)scene.content=fixture.project.frontstageWhiteboard.beats.filter(b=>b.sceneID===scene.id).map(b=>b.html).join('');
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.waitForSelector('#projects:not([hidden])');
 await page.locator('#import-project').setInputFiles({name:'Write navigation.frontstage',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 const sheet=page.locator('.continuous-editor'),desk=page.locator('.continuous-desk'),headings=sheet.locator('[data-heading-scene="1"]');
 const caret=()=>sheet.evaluate(n=>{const s=getSelection(),r=document.createRange(),p=s.anchorNode?.nodeType===3?s.anchorNode.parentElement:s.anchorNode;const line=p?.closest('[data-heading-scene]');if(!line)return null;r.selectNodeContents(line);r.setEnd(s.anchorNode,s.anchorOffset);return {offset:r.toString().length,beat:line.dataset.beatId};});
 await headings.first().selectText();let typed='';
 for(const char of 'ext. park - '){typed+=char;await page.keyboard.type(char);assert.equal(await headings.first().innerText(),typed.toUpperCase());assert.equal((await caret()).offset,typed.length);}
 await page.keyboard.type('night');assert.equal(await headings.first().innerText(),'EXT. PARK - NIGHT');assert.equal(await headings.last().innerText(),'EXT. PARK - NIGHT');assert.equal(await sheet.locator('[data-heading-scene]').count(),3);
 // Edit the later occurrence; the unchanged first occurrence must not win.
 await headings.last().selectText();await page.keyboard.type('int. hall - day');assert.equal(await headings.first().innerText(),'INT. HALL - DAY');assert.equal(await headings.last().innerText(),'INT. HALL - DAY');
 await page.keyboard.press('Escape');
 await headings.last().evaluate(n=>{const r=document.createRange();r.setStart(n.firstChild,5);r.setEnd(n.firstChild,9);getSelection().removeAllRanges();getSelection().addRange(r);});await page.keyboard.type('bridge');assert.equal(await headings.first().innerText(),'INT. BRIDGE - DAY');
 await headings.last().selectText();await page.keyboard.press('Backspace');assert.equal(await sheet.locator('[data-heading-scene]').count(),3);assert.equal(await page.locator('.simple-beat-card').count(),3);
 await page.keyboard.type('ext. தமிழ் வீடு - n');await page.keyboard.press('Enter');assert.equal(await headings.last().innerText(),'EXT. தமிழ் வீடு - NIGHT');
 await page.keyboard.press('Enter');assert.equal(await sheet.locator('[data-heading-scene]').count(),3);assert.equal(await sheet.evaluate(()=>{let n=getSelection().anchorNode;if(n?.nodeType===3)n=n.parentElement;return !!n?.closest('[data-heading-scene]');}),false);
 // Replacements cannot change the screenplay's body text or create scenes.
 assert.equal(await sheet.locator('.sc-action').count(),300);
 async function navigate(id){await page.locator(`.simple-beat-card[data-beat-id="${id}"] [data-card-field="title"]`).click();await page.waitForFunction(id=>document.querySelector('.continuous-editor').dataset.activeBeat===id,id);}
 async function centered(id){const geometry=await sheet.evaluate((n,id)=>{const p=n.querySelector('[data-beat-id="'+id+'"]'),d=n.closest('.continuous-desk'),r=p.getBoundingClientRect(),v=d.getBoundingClientRect();return {distance:Math.abs(r.top+r.height/2-v.top-d.clientTop-d.clientHeight/2),y:d.scrollTop,max:d.scrollHeight-d.clientHeight,x:d.scrollLeft,outer:document.scrollingElement.scrollTop};},id);assert.ok(geometry.distance<3||geometry.y<1||Math.abs(geometry.y-geometry.max)<2,JSON.stringify(geometry));return geometry;}
 await navigate('beat-2');const firstGeometry=await centered('beat-2');assert.ok(firstGeometry.y>0);assert.equal((await caret()).beat,'beat-2');
 await desk.evaluate(n=>n.scrollTop-=80);await navigate('beat-2');assert.ok((await centered('beat-2')).distance<3,'A scene already on screen must still be centered');
 await page.getByRole('button',{name:'Zoom in',exact:true}).click();await navigate('repeat');await centered('repeat');assert.equal((await caret()).beat,'repeat');
 await navigate('beat-1');assert.equal((await centered('beat-1')).y,0);
 // Composition defers card navigation instead of committing partial text to a new target.
 await headings.first().selectText();await sheet.dispatchEvent('compositionstart');await navigateWithoutWait('beat-2');assert.equal(await sheet.getAttribute('data-active-beat'),'beat-1');await sheet.dispatchEvent('compositionend');await page.waitForFunction(()=>document.querySelector('.continuous-editor').dataset.activeBeat==='beat-2');await centered('beat-2');
 async function navigateWithoutWait(id){await page.locator(`.simple-beat-card[data-beat-id="${id}"] [data-card-field="title"]`).click();}
 // Save/reopen keeps the shared heading and scene identities.
 await page.locator('#save').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Saved on this device'));await page.reload();await page.locator('#local-mode').click();await page.getByRole('button',{name:fixture.name+' · on this device',exact:true}).click();await page.locator('#view-mode').selectOption('edit');assert.equal(await page.locator('.continuous-editor [data-heading-scene="1"]').first().innerText(),'EXT. தமிழ் வீடு - NIGHT');assert.equal(await page.locator('.simple-beat-card').count(),3);
 // A hidden destination remains filtered until the user chooses the explicit reset.
 await page.getByText('Writing options',{exact:true}).click();await page.locator('.dedicated-script-tools summary').filter({hasText:/^Filter$/}).click();const filter=page.locator('.dedicated-script-tools').getByLabel('Filter script',{exact:true});await filter.fill('no-scene-matches-this-query');await filter.press('Tab');
 await page.waitForFunction(()=>document.querySelectorAll('.continuous-editor>[data-beat-id]').length===0);await navigateWithoutWait('beat-2');await page.getByRole('button',{name:'Reset filters and reveal',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.continuous-editor')?.dataset.activeBeat==='beat-2');await centered('beat-2');
 await mkdir(path.join(root,'build/parity'),{recursive:true});await page.screenshot({path:path.join(root,'build/parity/write-navigation.png')});assert.deepEqual(errors,[]);
 console.log('PASS: real heading typing/replacement, repeated occurrences, Tamil/time suggestions, unchanged bodies, centered scene navigation, zoom, composition deferral and reopen');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
