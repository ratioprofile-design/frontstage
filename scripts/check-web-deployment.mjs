import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const origin = 'https://frontstage-five.vercel.app';
const digest = value => createHash('sha256').update(value).digest('hex');
const files = ['index.html', 'app.js', 'merge.js', 'board-operations.js', 'style.css', 'workspace-design.js', 'workspace-design.css', 'workspace-model.js', 'workspaces.js', 'pagination.js', 'workspaces.css', 'screenplay-editor.js', 'bamini.js'];
const expected = new Map(await Promise.all(files.map(async file => [file, digest(await readFile(path.join(root, 'build/web', file)))])));
let last = '';
for (let attempt = 1; attempt <= 12; attempt++) {
  try {
    for (const file of files) {
      const url = origin + (file === 'index.html' ? '/' : '/' + file);
      const response = await fetch(url, { signal: AbortSignal.timeout(10000), cache: 'no-store', redirect: 'error' });
      if (!response.ok) throw Error(`${file}: HTTP ${response.status}`);
      if (digest(Buffer.from(await response.arrayBuffer())) !== expected.get(file)) throw Error(`${file}: deployed content differs from this build`);
    }
    const config = await fetch(origin + '/config.js', { signal: AbortSignal.timeout(10000), cache: 'no-store', redirect: 'error' });
    if (!config.ok || !(await config.text()).startsWith('export const apiOrigin = ')) throw Error('Public service configuration is missing');
    const worker = await fetch(origin + '/sw.js', { signal: AbortSignal.timeout(10000), cache: 'no-store', redirect: 'error' });
    if (!worker.ok || !(await worker.text()).includes('const FRONTSTAGE_SHELL = ')) throw Error('Offline application shell is missing');
    const message = `PASS: ${origin} serves this browser build. Backend hosting/accounts/sync require a separately configured Swift service.`;
    console.log(message); await writeFile(path.join(root, 'build/web-deployment.txt'), message + '\n');
    process.exit(0);
  } catch (error) {
    last = error.message;
    console.log(`Deployment check ${attempt}/12: ${last}`);
    if (attempt < 12) await new Promise(resolve => setTimeout(resolve, 10000));
  }
}
const message = `Public browser deployment could not be verified: ${last}. Check the connected Vercel project's deployment and protection settings.`;
await writeFile(path.join(root, 'build/web-deployment.txt'), message + '\n');
console.error('::error::' + message);
process.exit(1);
