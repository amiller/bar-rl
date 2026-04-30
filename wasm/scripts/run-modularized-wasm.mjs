// Node wrapper for the browser-modularized spring-headless build (used by
// Pages: -sMODULARIZE=1 -sEXPORT_NAME=createSpring -sINVOKE_RUN=0). The
// build doesn't auto-run main when loaded as a script — you must call the
// exported factory and then callMain() with argv.
//
// Usage: node run-modularized-wasm.mjs <wasm-js-path> -- <argv...>
//
// Example:
//   node run-modularized-wasm.mjs build-wasm-browser-pthread/spring-headless.js \
//        -- --write-dir /home/.../BAR --isolation=true /tmp/replay.sdfz
//
// Streams print/printErr to stdout so desync-quick.py can grep DESYNC lines.
import { createRequire } from 'module';
const require = createRequire(import.meta.url);

const argv = process.argv.slice(2);
const dashIdx = argv.indexOf('--');
if (dashIdx < 0) { console.error('usage: run-modularized-wasm.mjs <wasm-js> -- <argv...>'); process.exit(2); }
const wasmJs = argv[0];
const engineArgv = argv.slice(dashIdx + 1);

// Force a node-friendly ENVIRONMENT before the script defines the factory.
// The MODULARIZE wrapper checks ENVIRONMENT_IS_NODE inside, so we set
// it directly. Most browser-targeted builds still bundle node detection.
const factory = require(wasmJs);

const wasmDir = wasmJs.replace(/\/[^/]+$/, '/');
factory({
  print:    (s) => process.stdout.write(s + '\n'),
  printErr: (s) => process.stdout.write(s + '\n'),
  arguments: engineArgv,
  noInitialRun: false,
  locateFile: (p) => wasmDir + p,
  onAbort: (what) => { process.stdout.write(`[host] abort: ${what}\n`); process.exit(3); },
  onExit:  (code) => process.exit(code),
}).catch(e => { console.error('[host] factory error:', e); process.exit(4); });
