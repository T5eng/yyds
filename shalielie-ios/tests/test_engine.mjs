import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const engineSource = readFileSync(join(root, "engine", "engine.js"), "utf8");

const sandbox = {
  atob,
  btoa,
  TextEncoder,
  TextDecoder,
  Uint8Array,
  Int8Array,
  Uint16Array,
  Int16Array,
  Uint32Array,
  Int32Array,
  Float32Array,
  Float64Array,
  ArrayBuffer,
  DataView,
  Map,
  Set,
  WeakMap,
  Promise,
  JSON,
  Math,
  Error,
  console,
  Uint8ClampedArray,
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(engineSource, sandbox, { filename: "engine.js" });

const PSP = sandbox.PhotographicStylePort;
const fail = (msg) => {
  console.error(`FAIL  ${msg}`);
  process.exitCode = 1;
};
const pass = (msg) => console.log(`PASS  ${msg}`);

if (!PSP) fail("PhotographicStylePort global is missing");
else pass("engine registered PhotographicStylePort");

if (typeof PSP.VERSION === "string" && PSP.VERSION.includes("0.5")) pass(`VERSION ${PSP.VERSION}`);
else fail(`unexpected VERSION ${PSP && PSP.VERSION}`);

if (PSP.SOURCE === "nathanatgit/Shalielie") pass("SOURCE attribution");
else fail("SOURCE attribution missing");

const jpeg = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46]);
if (PSP.sniff(jpeg) === "jpeg") pass("sniff jpeg");
else fail(`sniff jpeg -> ${PSP.sniff(jpeg)}`);

const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
if (PSP.sniff(png) === "png") pass("sniff png");
else fail(`sniff png -> ${PSP.sniff(png)}`);

const heic = new Uint8Array(32);
heic[3] = 32;
heic.set([0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63], 4);
if (PSP.sniff(heic) === "heic") pass("sniff heic ftyp");
else fail(`sniff heic -> ${PSP.sniff(heic)}`);

const inspect = PSP.inspect(jpeg);
if (inspect.kind === "jpeg") pass("inspect jpeg");
else fail(`inspect jpeg -> ${JSON.stringify(inspect)}`);

async function expectCode(label, fn, code) {
  try {
    await fn();
    fail(`${label}: expected ${code}, resolved`);
  } catch (err) {
    const msg = err && err.message ? err.message : String(err);
    if (msg === code) pass(`${label}: ${code}`);
    else fail(`${label}: expected ${code}, got ${msg}`);
  }
}

await expectCode("port jpeg", () => PSP.port(jpeg), "NOT_HEIC");
await expectCode("port png", () => PSP.port(png), "NOT_HEIC");
await expectCode("port tiny heic", () => PSP.port(heic), "UNSUPPORTED");

const b64 = Buffer.from(jpeg).toString("base64");
await expectCode("portBase64 jpeg", () => PSP.portBase64(b64), "NOT_HEIC");

if (typeof PSP.b64ToU8 === "function") {
  const round = PSP.u8ToB64(jpeg);
  const back = PSP.b64ToU8(round);
  if (Buffer.from(back).equals(Buffer.from(jpeg))) pass("b64 round-trip");
  else fail("b64 round-trip mismatch");
}

if (process.exitCode) {
  console.error("\nengine tests failed");
  process.exit(1);
}
console.log("\nengine tests passed");
