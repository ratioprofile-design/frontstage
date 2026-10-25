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
 await page.locator('#import-project').setInputFiles(path.join(root,'Tests/Fixtures/workspace-parity.frontstage'));await page.waitForSelector('#workspace:not([hidden])');
 await page.locator('#view-mode').selectOption('board');const before=await page.locator('#blocks>[data-block-id]').count();
 await page.locator('#add-beat').click();const popup=page.locator('.beat-popup.active');await popup.getByLabel('Beat name',{exact:true}).fill('Delete this loose beat');const id=await popup.getAttribute('data-beat-id');await popup.getByRole('button',{name:'Close editor',exact:true}).click();
 const tile=page.locator(`#blocks [data-beat-id="${id}"]`);assert.equal(await tile.count(),1);assert.equal(await page.locator('#blocks>[data-block-id]').count(),before+1);
 await tile.click({button:'right'});await page.getByRole('menuitem',{name:'Delete Beat',exact:true}).click();assert.equal(await tile.count(),0);assert.equal(await page.locator('#blocks>[data-block-id]').count(),before);
 await page.locator('#undo').click();assert.equal(await tile.count(),1);assert.equal(await page.locator('#blocks>[data-block-id]').count(),before+1);
 await page.locator('#redo').click();assert.equal(await tile.count(),0);assert.equal(await page.locator('#blocks>[data-block-id]').count(),before);
 await page.locator('#undo').click();await tile.click();await page.locator('#canvas').focus();await page.keyboard.press('Delete');assert.equal(await tile.count(),0);assert.equal(await page.locator('#blocks>[data-block-id]').count(),before);
 await page.reload();await page.locator('#local-mode').click();await page.getByRole('button',{name:/The Invitation/}).first().click();await page.locator('#view-mode').selectOption('board');assert.equal(await tile.count(),0);assert.equal(await page.locator('#blocks>[data-block-id]').count(),before);
 assert.deepEqual(errors,[]);console.log('PASS: fresh loose beat deletion by context menu and keyboard leaves no block; undo/redo and reload preserve the correct containers');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
