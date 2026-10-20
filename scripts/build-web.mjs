import { mkdir, cp, writeFile, rm } from 'node:fs/promises';
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
console.log('Built browser client in build/web. Shared service configuration is ' + (origin ? 'provided.' : 'entered at sign-in.'));
