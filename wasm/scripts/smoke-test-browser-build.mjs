// Smoke test: load the browser-targeted WASM build under Node with MEMFS,
// confirm the module instantiates and FS is exposed. Doesn't try to run a
// replay (no base content planted) — just verifies the entry shape works.
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const path = await import('path');
const url  = await import('url');
const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const buildDir = path.resolve(__dirname, '../build-wasm-browser');

// MODULARIZE'd output isn't ESM-importable directly in Node 22; load via require.
const createSpring = require(path.join(buildDir, 'spring-headless.js'));

const Module = await createSpring({
  print: (s) => console.log('[engine]', s),
  printErr: (s) => console.log('[engine.err]', s),
  locateFile: (p) => path.join(buildDir, p),
});

console.log('---');
console.log('boot ok. FS:', typeof Module.FS, 'callMain:', typeof Module.callMain);
console.log('FS.writeFile/readFile:', typeof Module.FS.writeFile, typeof Module.FS.readFile);

// Plant a tiny file in MEMFS; readback to prove it works.
Module.FS.mkdir('/work');
Module.FS.writeFile('/work/hello.txt', new Uint8Array([72, 73, 10]));
const back = Module.FS.readFile('/work/hello.txt');
console.log('plant+read OK:', back.length, 'bytes,', new TextDecoder().decode(back).trim());
console.log('SMOKE TEST PASSED');
process.exit(0);
