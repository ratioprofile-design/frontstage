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
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));fixture.project.frontstageWhiteboard.dependencies=[];fixture.project.frontstageWhiteboard.blocks.forEach((b,i)=>{b.position={x:60+i*300,y:60};b.collapsed=false;});
 await page.goto('http://127.0.0.1:17845');await page.locator('#local-mode').click();await page.locator('#back').click();await page.locator('#import-project').setInputFiles({name:'Push.dot',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(fixture))});await page.waitForSelector('#workspace:not([hidden])');
 const canvas=page.locator('#canvas'),target=page.locator('#blocks [data-block-id="'+fixture.project.frontstageWhiteboard.blocks[1].id+'"]');
 const download=async()=>{const event=page.waitForEvent('download');await page.locator('#download').evaluate(n=>n.click());const file=await event;return JSON.parse(await readFile(await file.path(),'utf8'));};
 const before=await download(),bounds=await canvas.boundingBox(),original=await target.boundingBox();
 await page.getByRole('button',{name:'Push',exact:true}).click();
 const x=original.x-25,y=bounds.y+Math.min(150,bounds.height-50);await page.mouse.move(x,y);await page.mouse.down();await page.mouse.move(x+80,y,{steps:6});
 assert.ok(await canvas.evaluate(n=>n.dataset.pushPreview==='true'));assert.ok((await target.boundingBox()).x-original.x>70);assert.deepEqual((await download()).project.frontstageWhiteboard,before.project.frontstageWhiteboard);
 await page.keyboard.press('Escape');await page.mouse.up();assert.ok(Math.abs((await target.boundingBox()).x-original.x)<2);assert.deepEqual((await download()).project.frontstageWhiteboard,before.project.frontstageWhiteboard);
 await page.mouse.move(x,y);await page.mouse.down();await page.mouse.move(x+80,y,{steps:6});await page.mouse.up();const moved=await download();assert.equal(moved.project.frontstageWhiteboard.blocks[1].position.x,before.project.frontstageWhiteboard.blocks[1].position.x+80);
 await page.locator('#undo').click();assert.deepEqual((await download()).project.frontstageWhiteboard,before.project.frontstageWhiteboard);await page.locator('#redo').click();assert.deepEqual((await download()).project.frontstageWhiteboard,moved.project.frontstageWhiteboard);
 assert.deepEqual(errors,[]);console.log('PASS: live Push preview leaves saved data unchanged; Escape cancels; release is one undoable operation');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
