#!/usr/bin/env bash
# Benchmarks the WASM build against arXiv tarballs using BusytexPipeline via Node.js.
#
# Usage:
#   ./bench_wasm.sh <busytex.js> <texlive-basic.js> <arxiv-tar> [arxiv-tar ...]
#
# Without remote server (texlive-basic packages only):
#   wget -nc https://github.com/busytex/busytex/releases/download/busytexbenchset/arXiv_src_1702_001.tar
#   ./bench_wasm.sh dist-wasm/busytex.js dist-wasm/texlive-basic.js arXiv_src_1702_001.tar
#
# With remote texlive server (recommended for realistic results):
#   Start server in one terminal:
#     TEXMF_ROOT=./build/texlive-full/texmf-dist python3 texlive-server/wsgi.py
#   Run benchmark in another:
#     TEXLIVE_REMOTE_ENDPOINT=http://localhost:8070 \
#     ./bench_wasm.sh dist-wasm/busytex.js dist-wasm/texlive-basic.js arXiv_src_1702_001.tar
#
# Multiple tarballs:
#   for tar in arXiv_src_1702_001.tar arXiv_src_2202_001.tar arXiv_src_2302_001.tar arXiv_src_2402_001.tar; do
#     wget -nc https://github.com/busytex/busytex/releases/download/busytexbenchset/$tar
#   done
#   TEXLIVE_REMOTE_ENDPOINT=http://localhost:8070 \
#   ./bench_wasm.sh dist-wasm/busytex.js dist-wasm/texlive-basic.js \
#     arXiv_src_1702_001.tar arXiv_src_2202_001.tar arXiv_src_2302_001.tar arXiv_src_2402_001.tar
set -euo pipefail

BUSYTEX_JS=${1:?Usage: $0 <busytex.js> <texlive-basic.js> <arxiv-tar>...}
TEXLIVE_JS=${2:?Usage: $0 <busytex.js> <texlive-basic.js> <arxiv-tar>...}
shift 2
ARXIV_TARS=("$@")

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
REMOTE_ENDPOINT="${TEXLIVE_REMOTE_ENDPOINT:-}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0
SKIP=0
TOTAL=0

for tar_path in "${ARXIV_TARS[@]}"; do
    while IFS= read -r -d '' member; do
        name=$(basename "$member" .gz)
        outdir="$TMPDIR/$name"
        mkdir -p "$outdir"

        python3 - "$tar_path" "$member" "$outdir" 2>/dev/null << 'PYEOF'
import gzip, sys, tarfile, io, os
tar_path, member, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
with tarfile.open(tar_path) as tf:
    data = gzip.open(tf.extractfile(tf.getmember(member))).read()
try:
    tarfile.open(fileobj=io.BytesIO(data)).extractall(outdir, filter='data')
except TypeError:
    tarfile.open(fileobj=io.BytesIO(data)).extractall(outdir)
except Exception:
    with open(os.path.join(outdir, os.path.basename(member).replace('.gz', '.tex')), 'wb') as f:
        f.write(data)
PYEOF

        tex_file=$(python3 -c "
import os, sys
d = sys.argv[1]
hits = [f for f in os.listdir(d) if f.endswith('.tex') and b'\\\\begin{document}' in open(os.path.join(d,f),'rb').read()]
print(hits[0] if hits else '')
" "$outdir" 2>/dev/null) || tex_file=""

        if [ -z "$tex_file" ]; then
            SKIP=$((SKIP + 1))
            echo "SKIP  $name  (no main tex file)"
            continue
        fi

        TOTAL=$((TOTAL + 1))

        files_json_path="$TMPDIR/${name}.json"
        python3 - "$outdir" "$files_json_path" << 'PYEOF'
import os, sys, json, base64
d, out = sys.argv[1], sys.argv[2]
files = []
for root, _, fnames in os.walk(d):
    for f in fnames:
        full = os.path.join(root, f)
        rel  = os.path.relpath(full, d)
        try:
            raw = open(full, 'rb').read()
            files.append({'path': rel, 'contents': base64.b64encode(raw).decode('ascii'), 'binary': True})
        except Exception:
            pass
with open(out, 'w') as fh:
    json.dump(files, fh)
PYEOF

        result=$(node - "$SCRIPT_DIR" "$BUSYTEX_JS" "$TEXLIVE_JS" "$tex_file" "$files_json_path" "$REMOTE_ENDPOINT" << 'JSEOF' 2>/dev/null
const fs   = require('fs');
const path = require('path');

const SCRIPT_DIR      = process.argv[2];
const BUSYTEX_JS      = path.resolve(process.argv[3]);
const TEXLIVE_JS      = path.resolve(process.argv[4]);
const TEX_FILE        = process.argv[5];
const FILES           = JSON.parse(fs.readFileSync(process.argv[6], 'utf8')).map(f => ({
    path: f.path,
    contents: Buffer.from(f.contents, 'base64'),
}));
const REMOTE_ENDPOINT = process.argv[7] || '';
const BUSYTEX_WASM    = BUSYTEX_JS.replace('.js', '.wasm');

global.self       = global;
global.indexedDB  = undefined;

global.fetch = async (url) => {
    const filePath = url.startsWith('file://') ? new URL(url).pathname : String(url);
    const data = fs.readFileSync(filePath);
    return {
        ok: true, status: 200,
        text:        () => Promise.resolve(data.toString('utf8')),
        arrayBuffer: () => Promise.resolve(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)),
    };
};

WebAssembly.compileStreaming = async (fetchPromise) => {
    const resp = await fetchPromise;
    return WebAssembly.compile(await resp.arrayBuffer());
};

global.XMLHttpRequest = class {
    open(method, url) { this._url = url; }
    send() {
        if (!this._url || !REMOTE_ENDPOINT) { this.status = 404; this.response = null; return; }
        try {
            require('child_process').execSync(
                `curl -sf --max-time 10 -o /tmp/kpse_remote_fetch "${this._url}"`,
                { stdio: ['ignore', 'pipe', 'ignore'] }
            );
            this.status = 200;
            this.response = fs.readFileSync('/tmp/kpse_remote_fetch');
        } catch (_) { this.status = 404; this.response = null; }
    }
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

async function run() {
    console.log   = () => {};
    console.error = () => {};

    const pipeline = new BusytexPipeline(
        BUSYTEX_JS, BUSYTEX_WASM,
        [TEXLIVE_JS], [TEXLIVE_JS],
        [], () => {}, () => {}, true, ScriptLoaderNode
    );
    await pipeline.on_initialized_promise;

    const tic    = Date.now();
    const result = await pipeline.compile(FILES, TEX_FILE, false, false, false, BusytexPipeline.VerboseSilent, 'pdftex_bibtex8', [], REMOTE_ENDPOINT);
    const elapsed = Date.now() - tic;

    process.stdout.write(
        result.exit_code === 0 && result.pdf
            ? 'OK ' + elapsed + 'ms ' + result.pdf.length + 'bytes\n'
            : 'FAIL\n'
    );
}

run().catch(() => process.stdout.write('FAIL\n'));
JSEOF
        ) || result="FAIL"

        if [[ "${result%% *}" == "OK" ]]; then
            PASS=$((PASS + 1))
            echo "OK    $name  ($result)"
        else
            FAIL=$((FAIL + 1))
            echo "FAIL  $name"
        fi
    done < <(python3 -c "
import tarfile, sys
with tarfile.open(sys.argv[1]) as tf:
    for m in tf.getmembers():
        if m.name.endswith('.gz'):
            sys.stdout.buffer.write(m.name.encode() + b'\x00')
" "$tar_path" 2>/dev/null)
done

echo ""
echo "total=$TOTAL ok=$PASS fail=$FAIL skip=$SKIP"