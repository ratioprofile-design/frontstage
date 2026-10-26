import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url)),publicDir=path.join(root,'Server/Public'),output=path.join(root,'build/parity');await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{try{const relative=req.url==='/'?'index.html':decodeURIComponent(req.url.slice(1));if(relative.includes('/')||relative.includes('..')){res.writeHead(404);res.end();return;}const content=await readFile(path.join(publicDir,relative));res.setHeader('Content-Type',relative.endsWith('.js')?'application/javascript':relative.endsWith('.css')?'text/css':'text/html');res.end(content);}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(17845,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({viewport:{width:1440,height:950}}),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();
 await page.locator('#import-project').setInputFiles(path.join(root,'Tests/Fixtures/write-panels.frontstage'));await page.waitForSelector('#workspace:not([hidden])');await page.locator('#view-mode').selectOption('edit');
 const editor=page.getByRole('textbox',{name:'Screenplay',exact:true});await editor.waitFor();assert.equal(await page.locator('.writing-scene-fields').count(),0);
 await editor.locator('[data-heading-scene="1"]').fill('EXT. RIVER - NIGHT');await editor.locator('[data-beat-id="beat-1"]:not([data-heading-scene])').first().fill('தமிழ் — continuous screenplay.');
 await page.getByRole('navigation',{name:'Screenplay elements'}).getByRole('button',{name:'Character',exact:true}).click();assert.ok(await editor.locator('.sc-character').count()>0);
 const right=page.locator('.write-right');await right.getByRole('button',{name:'Notes',exact:true}).click();await right.getByRole('button',{name:'Add Note',exact:true}).click();const note=right.getByRole('textbox',{name:'Note text',exact:true}).last();await note.click();await page.keyboard.type('**Hello**');assert.equal(await note.locator('strong,b').innerText(),'Hello');
 await page.locator('#view-mode').selectOption('board');await page.locator('#blocks [data-beat-id="beat-1"]').click({button:'right'});await page.getByRole('menuitem',{name:'Omit Beat',exact:true}).click();assert.equal(await page.locator('#blocks [data-beat-id="beat-1"]').evaluate(n=>getComputedStyle(n).backgroundColor),'rgb(119, 119, 119)');
 await page.locator('#view-mode').selectOption('edit');assert.equal(await page.locator('.continuous-editor [data-beat-id="beat-1"]').count(),0);
 await page.locator('#view-mode').selectOption('board');await page.locator('#blocks [data-beat-id="beat-1"]').click({button:'right'});await page.getByRole('menuitem',{name:'Pull Out Beat',exact:true}).click();assert.equal(await page.locator('#blocks [data-beat-id="beat-1"]').count(),0);
 await page.locator('#view-mode').selectOption('studio');await page.getByLabel('Workspace',{exact:true}).selectOption('pulledOut');await page.getByRole('button',{name:'Restore Beat',exact:true}).click();await page.locator('#view-mode').selectOption('board');assert.equal(await page.locator('#blocks [data-beat-id="beat-1"]').count(),1);
 await page.screenshot({path:path.join(output,'continuous-inclusion.png')});assert.deepEqual(errors,[]);console.log('PASS: continuous screenplay, inline headings, toolbar, live Markdown, omission and Research restoration');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
