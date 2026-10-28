import {createServer} from 'node:http';
import {readFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const require=createRequire(import.meta.url),{chromium}=require(process.env.FRONTSTAGE_PLAYWRIGHT_MODULE||'playwright');
const root=fileURLToPath(new URL('../../',import.meta.url)),publicRoot=path.join(root,'build/web');
const server=createServer(async(req,res)=>{try{
 const name=new URL(req.url,'http://localhost').pathname,relative=name==='/'?'index.html':name.slice(1),file=path.resolve(publicRoot,relative);
 if(!file.startsWith(publicRoot+path.sep))throw Error();
 const type={'.js':'application/javascript','.css':'text/css','.png':'image/png','.ico':'image/x-icon','.json':'application/json','.html':'text/html'}[path.extname(file)];
 if(!type)throw Error();res.setHeader('Content-Type',type);res.end(await readFile(file));
}catch{res.writeHead(404);res.end();}});
await new Promise(resolve=>server.listen(17845,'127.0.0.1',resolve));let browser;
try{
 browser=await chromium.launch({executablePath:process.env.FRONTSTAGE_CHROMIUM||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':chromium.executablePath()),headless:true,args:['--no-sandbox']});
 const context=await browser.newContext({viewport:{width:1440,height:950},colorScheme:'light'}),page=await context.newPage(),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:17845');
 assert.match(await page.title(),/^DOT/);
 assert.equal(await page.locator('img[alt="DOT"]').evaluate(n=>n.complete&&n.naturalWidth>0),true);
 assert.ok((await page.locator('link[rel=manifest]').getAttribute('href')).endsWith('manifest-light.json'));
 await page.emulateMedia({colorScheme:'dark'});
 await page.waitForFunction(()=>document.querySelector('link[rel=manifest]').getAttribute('href').endsWith('manifest-dark.json'));
 // Upgrade fixture uses the existing DB and preference keys, not a newly named database.
 const fixture=JSON.parse(await readFile(path.join(root,'Tests/Fixtures/write-panels.frontstage'),'utf8'));
 await page.evaluate(async fixture=>{
   const db=await new Promise(resolve=>{const r=indexedDB.open('frontstage-offline',1);r.onsuccess=()=>resolve(r.result);});
   await new Promise(resolve=>{const tx=db.transaction('projects','readwrite');tx.objectStore('projects').put({id:'pre-dot-project',doc:fixture,base:fixture,revision:0,local:true,dirty:false,name:fixture.name});tx.oncomplete=resolve;});
   localStorage.setItem('frontstage-script-dedicated',JSON.stringify({zoom:1.2,theme:'Warm',display:'Final Script'}));
 },fixture);
 await page.locator('#local-mode').click();
 await page.getByRole('button',{name:fixture.name+' · on this device',exact:true}).click();
 await page.locator('#view-mode').selectOption('edit');
 assert.ok((await page.locator('.continuous-editor').textContent()).length>0);
 const theme=await page.evaluate(()=>JSON.parse(localStorage.getItem('frontstage-script-dedicated')));
 assert.equal(theme.zoom,1.2);assert.equal(theme.theme,'Warm');
 const expectedAccent=await page.evaluate(()=>{const n=document.createElement('span');n.style.color=CSS.supports('color','AccentColor')&&CSS.supports('color','AccentColorText')?'AccentColor':'Highlight';document.body.append(n);const c=getComputedStyle(n).color;n.remove();return c;});
 const active=page.locator('.screenplay-element-bar button[aria-pressed=true]').first();
 if(await active.count())assert.equal(await active.evaluate(n=>getComputedStyle(n).backgroundColor),expectedAccent);
 const waiting=page.waitForEvent('download');await page.locator('#download').click();const download=await waiting;
 assert.ok(download.suggestedFilename().endsWith('.dot'));
 const saved=JSON.parse(await readFile(await download.path(),'utf8'));
 assert.equal(saved.format,'frontstage');assert.equal(saved.version,1);
 assert.deepEqual(saved.project.beats[0].notes,fixture.project.beats[0].notes);
 assert.deepEqual(saved.project.frontstageWhiteboard.beats.map(b=>b.id),fixture.project.frontstageWhiteboard.beats.map(b=>b.id));
 await page.locator('#page-projects').click();
 await page.locator('#import-project').setInputFiles({name:'Word template.dot',mimeType:'application/msword',buffer:Buffer.from([0xd0,0xcf,0x11,0xe0])});
 await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Word templates'));
 await page.locator('#import-project').setInputFiles({name:'DOT project.dot',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(saved))});
 await page.waitForSelector('#workspace:not([hidden])');
 await page.reload();await page.locator('#local-mode').click();await page.getByRole('button',{name:fixture.name+' · on this device',exact:true}).first().waitFor();
 // Install/offline shell includes branding and keeps the pre-existing cache namespace.
 await page.waitForFunction(()=>navigator.serviceWorker.controller!=null);
 await page.evaluate(()=>navigator.serviceWorker.ready);
 const offlineAssets=await page.evaluate(async()=>{const names=await caches.keys(),cache=await caches.open(names.find(n=>n.startsWith('frontstage-shell-')));return Promise.all(['/brand/wordmark-dark.png','/brand/icon-dark-512.png','/manifest-dark.json','/branding.js','/project-files.js'].map(async name=>!!await cache.match(name)));});
 assert.ok(offlineAssets.every(Boolean));
 await context.setOffline(true);await page.reload();await page.waitForSelector('img[alt="DOT"]');
 assert.equal(await page.locator('img[alt="DOT"]').evaluate(n=>n.complete&&n.naturalWidth>0),true);
 await context.setOffline(false);
 await mkdir(path.join(root,'build/parity'),{recursive:true});await page.screenshot({path:path.join(root,'build/parity/dot-branding.png')});
 assert.deepEqual(errors,[]);console.log('PASS: DOT branding, system appearance/accent, .dot download/import, legacy offline data and preferences, Word rejection and offline icons');
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}
