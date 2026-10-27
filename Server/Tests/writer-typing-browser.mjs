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
 fixture.project.frontstageWhiteboard.beats[0].html='<p class="sc-line sc-action"><br></p>';
 fixture.project.frontstageWhiteboard.beats[1].html='<p class="sc-line sc-character">KAMAL KUMAR (O.S.)</p><p class="sc-line sc-dialogue">Hello.</p><p class="sc-line sc-character">கமல்</p><p class="sc-line sc-dialogue">வணக்கம்.</p>';
 for(const scene of fixture.project.beats)scene.content=fixture.project.frontstageWhiteboard.beats.filter(b=>b.sceneID===scene.id).map(b=>b.html).join('');
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();
 await page.locator('#import-project').setInputFiles({name:'Writer typing.frontstage',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 const sheet=page.locator('.continuous-editor'),body=()=>sheet.locator('[data-beat-id="beat-1"]:not([data-heading-scene])');
 const active=()=>sheet.evaluate(()=>{let n=getSelection()?.anchorNode;if(n?.nodeType===3)n=n.parentElement;while(n&&n.parentElement&&!n.parentElement.classList.contains('continuous-editor'))n=n.parentElement;return {text:n?.textContent,kind:n?.className,caret:getSelection()?.anchorOffset};});
 await body().first().click();const count=await body().count();await page.keyboard.press('Tab');
 assert.equal(await body().count(),count);assert.match((await active()).kind,/sc-character/);
 await page.keyboard.type('kam');assert.equal((await active()).text,'KAM');assert.ok(await page.getByRole('option',{name:'KAMAL KUMAR',exact:true}).isVisible());
 assert.equal((await active()).caret,3,'Showing a suggestion must not move the caret or select a suffix');
 await page.keyboard.press('Tab');assert.equal((await active()).text,'KAMAL KUMAR');assert.match((await active()).kind,/sc-character/);
 await page.keyboard.type(' (');assert.ok(await page.getByRole('option',{name:'(V.O.)',exact:true}).isVisible());await page.keyboard.press('Tab');assert.equal((await active()).text,'KAMAL KUMAR (V.O.)');
 await page.keyboard.press('Enter');assert.match((await active()).kind,/sc-dialogue/);assert.equal(await body().count(),count+1);
 await page.keyboard.type('First line.');await page.keyboard.press('Tab');assert.match((await active()).kind,/sc-parenthetical/);assert.equal(await body().count(),count+2);
 await page.keyboard.type('(over');await page.keyboard.press('Enter');assert.equal((await active()).text,'(over the phone)');await page.keyboard.press('Enter');assert.match((await active()).kind,/sc-dialogue/);
 const before=await body().count();await page.keyboard.press('Enter');assert.match((await active()).kind,/sc-action/);assert.equal(await body().count(),before);
 await page.keyboard.type('He walks.');await page.keyboard.press('ArrowLeft');await page.keyboard.press('ArrowLeft');await page.keyboard.press('Tab');assert.equal(await body().count(),before+1);assert.equal(await body().filter({hasText:'He walks.'}).count(),1);assert.match((await active()).kind,/sc-character/);
 await page.keyboard.type('kam');await page.keyboard.press('Enter');assert.match((await active()).kind,/sc-dialogue/);await page.keyboard.type('Again.');
 assert.equal(await body().locator('[data-auto-continuation="true"]').count(),0); // attribute lives on the paragraph itself
 assert.equal(await sheet.locator('[data-beat-id="beat-1"][data-auto-continuation="true"]').count(),1);
 const continuation=sheet.locator('[data-beat-id="beat-1"][data-auto-continuation="true"]');assert.equal(await continuation.evaluate(n=>getComputedStyle(n,'::after').content),'" (CONT\'D)"');assert.ok(!(await sheet.textContent()).includes("CONT'D"));
 const geometry=await sheet.locator('[data-beat-id="beat-1"].sc-character').first().evaluate(n=>{const s=getComputedStyle(n),p=getComputedStyle(n.parentElement),width=n.parentElement.clientWidth-parseFloat(p.paddingLeft)-parseFloat(p.paddingRight);return {indent:parseFloat(s.marginLeft)/width,weight:s.fontWeight};});assert.ok(Math.abs(geometry.indent-.33)<.01,JSON.stringify(geometry));assert.equal(geometry.weight,'400');
 // A committed cue is discovered without assigning a character in the popup.
 await page.keyboard.press('Enter');await page.keyboard.press('Tab');await page.keyboard.type('new tamil speaker');await page.keyboard.press('Enter');await page.keyboard.type('Spoken.');await page.keyboard.press('Enter');await page.keyboard.press('Tab');await page.keyboard.type('new');assert.ok(await page.getByRole('option',{name:'NEW TAMIL SPEAKER',exact:true}).isVisible());await page.keyboard.press('Escape');assert.equal((await active()).text,'NEW');
 // Suggestions replace only the edited slugline component.
 const heading=sheet.locator('[data-heading-scene="1"]');await heading.selectText();await page.keyboard.type('ext. park - n');assert.equal(await heading.innerText(),'EXT. PARK - N');await page.keyboard.press('Enter');assert.equal(await heading.innerText(),'EXT. PARK - NIGHT');await page.keyboard.press('Enter');assert.ok(!(await active()).kind.includes('sc-slugline'));
 await page.locator('.simple-beat-card[data-beat-id="beat-1"] [data-card-field="title"]').click();assert.equal(await sheet.locator('[data-active-heading="true"]').count(),1);assert.equal(await body().evaluateAll(nodes=>nodes.every(n=>getComputedStyle(n).backgroundColor==='rgba(0, 0, 0, 0)')),true);
 // A filtered-out intervening speaker must not create false continuations.
 const flags=await page.evaluate(async()=>{const {projectDialogue}=await import('/dialogue-rules.js');const {decorateDialogue}=await import('/dialogue-rules.js');const html=n=>`<p class="sc-character">${n}</p><p class="sc-dialogue">Text.</p>`;const doc={project:{frontstageWhiteboard:{layers:[],blocks:[],beats:[{id:'a',sceneID:1,order:0,html:html('A')},{id:'b',sceneID:1,order:1,html:html('B')},{id:'c',sceneID:1,order:2,html:html('A')}]}}};const flags=projectDialogue(doc).flags,root=document.createElement('div');root.innerHTML='<p class="sc-character" data-beat-id="a">A</p><p class="sc-dialogue">Text.</p><p class="sc-character" data-beat-id="c">A</p>';decorateDialogue(root,null,flags);return {flags,tokens:root.querySelectorAll('[data-auto-continuation]').length};});assert.deepEqual(flags.flags,{a:[false],b:[false],c:[false]});assert.equal(flags.tokens,0);
 await page.locator('#save').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Saved on this device'));await page.reload();await page.locator('#local-mode').click();await page.getByRole('button',{name:fixture.name+' · on this device',exact:true}).click();await page.locator('#view-mode').selectOption('edit');assert.equal(await page.locator('.continuous-editor [data-auto-continuation="true"]').count(),1);assert.ok(!(await page.locator('.continuous-editor').textContent()).includes("CONT'D"));
 await mkdir(path.join(root,'build/parity'),{recursive:true});await page.screenshot({path:path.join(root,'build/parity/writer-typing.png')});assert.deepEqual(errors,[]);
 console.log('PASS: real Writer Tab/Enter flow, no spacer paragraphs, name discovery, extensions, parentheticals, caret-safe suggestions, continuation presentation, filtered speakers, geometry, slugline highlight and reload');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
