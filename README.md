# TeXlyre-BusyTeX

TeXLive 2026 compiled into a single WebAssembly module, based on [busytex](https://github.com/busytex/busytex).

The corresponding WASM API for this build can be found at [texlyre-busytex](https://github.com/TeXlyre/texlyre-busytex).

To run the package server, refer to the [TeXLive server instructions](/texlive-server/README.md).

**Bundled engines and tools:**

* xetex, pdftex, luahbtex
* bibtex8, xdvipdfmx, makeindex
* kpsewhich, kpsestat, kpseaccess, kpsereadlink

**Supported targets:** `x86_64-linux` (static, musl) and `wasm32`.

---

## Usage

**Using prebuilt assets:**

```shell
mkdir -p dist-wasm
wget -P dist-wasm --backups=1 $(printf "https://github.com/TeXlyre/texlyre-busytex-build/releases/latest/download/%s " \
  busytex_pipeline.js busytex_worker.js \
  busytex.wasm busytex.js \
  texlive-basic.js texlive-basic.data \
  texlive-recommended.js texlive-recommended.data \
  texlive-extra.js texlive-extra.data)
```

**Using a local build:**

Follow the [build instructions](#building-from-source) first. The built assets will be placed in `dist-wasm/`.

**Run the example:**

```shell
python3 example/example.py --port 8183
```

Then open http://localhost:8183/example/example.html.

---

## Building from source

### Prerequisites

```shell
apt-get install -y \
  libnsl-dev build-essential coreutils cmake bash git \
  xz-utils wget perl gperf p7zip-full python3 gh strace \
  libarchive-tools curl dos2unix bubblewrap texlive-binaries
```

### Emscripten

```shell
git clone https://github.com/emscripten-core/emsdk
cd emsdk
./emsdk update-tags
./emsdk install tot
./emsdk activate tot
source emsdk_env.sh
cd ..
```

### Build

```shell
git clone https://github.com/TeXlyre/texlyre-busytex-build
cd texlyre-busytex-build

export MAKEFLAGS=-j8

make source/texlive.txt build/versions.txt
make native
make smoke-native
```

If you want to provide the TeXLive ISO directly instead of having `make source/texmfrepo.txt` download it, place it in the `source/` directory first:

```shell
wget -P source http://mirrors.ctan.org/systems/texlive/Images/texlive2026.iso
split -b2G -d source/texlive2026.iso source/texlive2026.iso.
```

```shell
make source/texmfrepo.txt
make build/texlive-basic.txt build/texlive-recommended.txt build/texlive-extra.txt build/texlive-full.txt
make wasm
make build/wasm/texlive-basic.js
make build/wasm/texlive-recommended.js
make build/wasm/texlive-extra.js
make wasm-postbuild-hyphenation-fmt
make smoke-wasm
make dist-native dist-wasm
```

### Clean

```shell
rm source/texlive.patched
make clean
```

---

## TeXLive package server

For packages not included in `texlive-basic`, `texlive-recommended`, or `texlive-extra`, a server can stream them on demand. The remote endpoint is configurable via the `compile()` method in `web/busytex_pipeline.js`.

Build the full TeXLive tree first:

```shell
make -B build/texlive-full.txt
make build/wasm/busytex.js
```

Then run the production server following the [server instructions](./texlive-server/README.md) from within the `texlive-server` directory.

---

## Roadmap

* mf-nowin
* LuaMetaTeX / LMTX (lua)
* tlmgr (perl)
* Biber (perl)
* mktexlsr, fmtutil, updmap (perl)

---

## License

TeXlyre-BusyTeX and the modifications applied to the build pipeline are licensed under the GNU Affero General Public License v3.0 (AGPL-3.0). Based on [busytex](https://github.com/busytex/busytex) (MIT). See [LICENSE](LICENSE) and [NOTICE](NOTICE).

---

## References

* [busytex](https://github.com/busytex/busytex)
* [busytex (pdftex and xetex) TL2025 update](https://github.com/SiglumProject/busytex)
* [pdftex.js](https://github.com/dmonad/pdftex.js)
* [xetex.js](https://github.com/lyze/xetex-js)
* [texlive.js](https://github.com/manuels/texlive.js/)
* [latexjs](https://github.com/latexjs/latexjs)
* [dvi2html](https://github.com/kisonecat/dvi2html), [web2js](https://github.com/kisonecat/web2js)
* [SwiftLaTeX](https://github.com/SwiftLaTeX/SwiftLaTeX)
* [JavascriptSubtitlesOctopus](https://github.com/Dador/JavascriptSubtitlesOctopus)
* [js-sha1](https://raw.githubusercontent.com/emn178/js-sha1)
* [BLFS TeXLive](http://www.linuxfromscratch.org/blfs/view/svn/pst/texlive.html)
* latexmk: [CTAN](https://ctan.org/tex-archive/support/latexmk), [docs](https://mg.readthedocs.io/latexmk.html), [latexmk.py](https://github.com/schlamar/latexmk.py), [fork](https://github.com/JanKanis/latexmk.py), [PR #11](https://github.com/schlamar/latexmk.py/pull/11)
* [TeX::AutoTeX::File](https://metacpan.org/release/TSCHWAND/TeX-AutoTeX-v0.906.0/view/lib/TeX/AutoTeX/File.pm)