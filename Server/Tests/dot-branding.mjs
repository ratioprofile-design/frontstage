import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {parseProjectFile,projectFilename} from '../Public/project-files.js';
const root=new URL('../../',import.meta.url),read=name=>readFile(new URL(name,root));
const original=JSON.parse(await read('Tests/Fixtures/write-panels.frontstage'));
assert.deepEqual(parseProjectFile(JSON.stringify(original),'story.dot'),original);
assert.deepEqual(parseProjectFile(JSON.stringify(original),'story.DOT'),original);
assert.deepEqual(parseProjectFile(JSON.stringify(original),'story.frontstage'),original);
assert.throws(()=>parseProjectFile('Word binary template','story.dot'),/Word templates/);
assert.throws(()=>parseProjectFile('{"beats":[]}','story.dot'),/not a DOT project/);
assert.equal(projectFilename('தமிழ்/Story'),'தமிழ்-Story.dot');
const artwork=JSON.parse(await read('Resources/Brand/artwork.json'));
for(const [file,hash] of Object.entries(artwork.sources))assert.equal(createHash('sha256').update(await read('Resources/Brand/Originals/'+file)).digest('hex'),hash);
for(const theme of ['light','dark']){
 const manifest=JSON.parse(await read('Server/Public/manifest-'+theme+'.json'));
 assert.equal(manifest.name,'DOT');assert.equal(manifest.id,'/');
 for(const icon of manifest.icons){const bytes=await read('Server/Public'+icon.src);assert.equal(bytes.readUInt32BE(16),Number(icon.sizes.split('x')[0]));}
 assert.equal((await read('Resources/Brand/dot-'+theme+'.icns')).subarray(0,4).toString(),'icns');
}
const info=(await read('Resources/Info.plist')).toString();
assert.match(info,/<string>design.ratioprofile.frontstage<\/string>/);
assert.match(info,/<string>Alternate<\/string>/);assert.match(info,/<string>DOT<\/string>/);
const html=(await read('Server/Public/index.html')).toString();
assert.match(html,/alt="DOT"/);assert.match(html,/accept=".dot,.frontstage,.backstage,.json"/);
const sw=(await read('Server/Public/sw.js')).toString();
for(const name of await readdir(new URL('Server/Public/brand/',root)))assert.ok(sw.includes('/brand/'+name),'Offline branding asset: '+name);
assert.match(sw,/frontstage-shell-/);
console.log('PASS: DOT artwork hashes, icon dimensions, manifests, stable identity, legacy compatibility, Word rejection and offline asset inventory');
