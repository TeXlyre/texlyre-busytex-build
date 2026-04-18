#!/usr/bin/env bash
# Smoke-tests the WASM build using Node.js by compiling example/example.tex with each engine.
# Usage: ./test_wasm.sh <path-to-busytex.js> <path-to-texlive-basic.js>
set -euo pipefail

BUSYTEX_JS=${1:?Usage: $0 <busytex.js> <texlive-basic.js>}
TEXLIVE_JS=${2:?Usage: $0 <busytex.js> <texlive-basic.js>}
SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)

node - "$SCRIPT_DIR" "$BUSYTEX_JS" "$TEXLIVE_JS" << 'JSEOF'
const fs   = require('fs');
const path = require('path');

const SCRIPT_DIR   = process.argv[2];
const BUSYTEX_JS   = path.resolve(process.argv[3]);
const TEXLIVE_JS   = path.resolve(process.argv[4]);
const BUSYTEX_WASM = BUSYTEX_JS.replace('.js', '.wasm');

global.self = global;
global.indexedDB = undefined;

global.fetch = async (url) => {
    const filePath = url.startsWith('file://') ? new URL(url).pathname : String(url);
    const data = fs.readFileSync(filePath);
    const text        = () => Promise.resolve(data.toString('utf8'));
    const arrayBuffer = () => Promise.resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
    return { ok: true, status: 200, text, arrayBuffer };
};

WebAssembly.compileStreaming = async (fetchPromise) => {
    const resp = await fetchPromise;
    const buf  = await resp.arrayBuffer();
    return WebAssembly.compile(buf);
};

global.XMLHttpRequest = class {
    open(method, url) { this._url = url; }
    send() { this.status = 404; this.response = null; }
    get responseType() { return this._responseType || ''; }
    set responseType(v) { this._responseType = v; }
    set timeout(_) {}
};

const ScriptLoaderNode = (src) => {
    const factory = require(src);
    const name = path.basename(src, '.js');
    if (typeof factory === 'function' && !global[name])
        global[name] = factory;
    return Promise.resolve();
};

const pipelineCode = fs.readFileSync(path.join(SCRIPT_DIR, 'web/busytex_pipeline.js'), 'utf8');
const BusytexPipeline = (new Function(pipelineCode + '\nreturn BusytexPipeline;'))();

const _consoleLog = console.log;
const _consoleError = console.error;

async function run() {
    const texFiles = [
        { path: 'example.tex', contents: fs.readFileSync(path.join(SCRIPT_DIR, 'example/example.tex'), 'utf8') },
        { path: 'example.bib', contents: fs.readFileSync(path.join(SCRIPT_DIR, 'example/example.bib'), 'utf8') },
    ];

    const drivers = [
        { name: 'pdflatex',   driver: 'pdftex_bibtex8' },
        { name: 'xelatex',    driver: 'xetex_bibtex8_dvipdfmx' },
        { name: 'luahblatex', driver: 'luahbtex_bibtex8' },
    ];

    let allOk = true;

    for (const { name, driver } of drivers) {
        _consoleLog('\n--- ' + name + ' ---');
        try {
            console.log   = () => {};
            console.error = () => {};

            const pipeline = new BusytexPipeline(
                BUSYTEX_JS,
                BUSYTEX_WASM,
                [TEXLIVE_JS],
                [TEXLIVE_JS],
                [],
                () => {},
                () => {},
                true,
                ScriptLoaderNode
            );

            await pipeline.on_initialized_promise;

            const result = await pipeline.compile(texFiles, 'example.tex', false, false, false, BusytexPipeline.VerboseSilent, driver, []);

            console.log   = _consoleLog;
            console.error = _consoleError;

            if (result.exit_code !== 0 || !result.pdf) {
                _consoleError('FAIL: ' + name + ' (exit=' + result.exit_code + ', pdf=' + !!result.pdf + ')');
                _consoleError(result.log.slice(-2000));
                allOk = false;
            } else {
                _consoleLog('OK:   ' + name + ' (' + result.pdf.length + ' bytes)');
            }
        } catch (err) {
            console.log   = _consoleLog;
            console.error = _consoleError;
            _consoleError('FAIL: ' + name + ' threw: ' + err.message);
            if (err.stack) _consoleError(err.stack);
            allOk = false;
        }
    }

    process.exit(allOk ? 0 : 1);
}

run().catch(err => { console.log = _consoleLog; console.error = _consoleError; _consoleError(err); process.exit(1); });
JSEOF