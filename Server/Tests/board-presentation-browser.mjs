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
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));fixture.project.frontstageWhiteboard.beats[0].characters=['MAYA','DARA'];for(const beat of fixture.project.frontstageWhiteboard.beats)beat.tags=['Hope'];
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.locator('#import-project').setInputFiles({name:'Presentation.dot',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.locator('#blocks [data-beat-id="beat-2"]').waitFor();
 const download=async()=>{const event=page.waitForEvent('download');await page.locator('#download').evaluate(n=>n.click());return JSON.parse(await readFile(await (await event).path(),'utf8'));};
 const before=await download(),colors=page.getByLabel('Beat color display',{exact:true}),flows=page.getByLabel('Whiteboard FlowLines',{exact:true});
 await colors.selectOption('characters');assert.equal(await page.locator('#blocks [data-beat-id="beat-1"]').getAttribute('data-color-tracks'),'DARA, MAYA');assert.ok((await page.locator('#blocks [data-beat-id="beat-1"]').getAttribute('style')).includes('linear-gradient'));assert.deepEqual(await download(),before);
 await flows.selectOption(JSON.stringify(['tags','Hope']));assert.equal(await page.locator('#links [data-flow-cause]').count(),1);assert.equal(await page.locator('#links [data-edge-id]').count(),1);assert.deepEqual(await download(),before);
 await page.locator('#blocks [data-beat-id="beat-2"]').click({button:'right'});await page.getByRole('menuitem',{name:'Omit Beat',exact:true}).click();assert.equal(await page.locator('#links [data-flow-cause]').count(),0);assert.ok(!(await page.locator('#blocks [data-beat-id="beat-2"]').getAttribute('style')).includes('linear-gradient'));await page.locator('#undo').click();assert.equal(await page.locator('#links [data-flow-cause]').count(),1);assert.deepEqual(await download(),before);
 await page.locator('#save').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Saved on this device'));await page.reload();await page.locator('#local-mode').click();await page.getByRole('button',{name:fixture.name+' · on this device',exact:true}).click();await page.locator('#blocks [data-beat-id="beat-2"]').waitFor();assert.equal(await colors.inputValue(),'characters');assert.equal(await flows.inputValue(),JSON.stringify(['tags','Hope']));assert.equal(await page.locator('#links [data-flow-cause]').count(),1);
 assert.deepEqual(errors,[]);console.log('PASS: persistent local character/tag colors and FlowLines, unchanged saved data, omission, undo and reload');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
