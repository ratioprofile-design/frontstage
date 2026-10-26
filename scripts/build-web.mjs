import { mkdir, cp, writeFile, rm, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.join(root, 'build/web');
let origin = (process.env.FRONTSTAGE_API_ORIGIN || '').trim();
if (origin) {
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || !['', '/'].includes(url.pathname)) {
    throw Error('FRONTSTAGE_API_ORIGIN must be an HTTPS origin without credentials, path, query or fragment.');
  }
  origin = url.origin;
}
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(path.join(root, 'Server/Public'), output, { recursive: true });
await writeFile(path.join(output, 'config.js'), `export const apiOrigin = ${JSON.stringify(origin)};\n`);
const hash = createHash('sha256');
for (const file of ['index.html', 'app.js', 'merge.js', 'board-operations.js', 'story-timeline.js', 'config.js', 'style.css', 'workspace-design.js', 'workspace-design.css', 'workspace-model.js', 'workspaces.js', 'pagination.js', 'workspaces.css', 'screenplay-editor.js', 'scene-model.js', 'script-inclusion.js', 'continuous-script.js', 'live-markdown.js', 'write-panels.js', 'write-panel-model.js', 'script-filter.js', 'bamini.js']) {
  hash.update(file); hash.update(await readFile(path.join(output, file)));
}
const worker = await readFile(path.join(output, 'sw.js'), 'utf8');
await writeFile(path.join(output, 'sw.js'), worker.replace('__FRONTSTAGE_BUILD__', hash.digest('hex').slice(0, 20)));
console.log('Built browser client in build/web. Shared service configuration is ' + (origin ? 'provided.' : 'entered at sign-in.'));
