# TeXlyre-BusyTeX

TeX Live 2026 compiled into a single fully static binary (x86\_64-linux) and a WebAssembly module, based on [busytex](https://github.com/busytex/busytex).

Bundled engines and tools:

* xetex, pdftex, luahbtex
* bibtex8, xdvipdfmx, makeindex
* kpsewhich, kpsestat, kpseaccess, kpsereadlink

Supported targets: `x86\_64-linux` (static, musl) and `wasm32`.

## License

AGPL-3.0-or-later. Based on [busytex](https://github.com/busytex/busytex) (MIT). See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Usage

### WASM (browser)

Download the latest release assets and serve the example:

```shell
mkdir -p dist
wget -P dist --backups=1 $(printf "https://github.com/busytex/busytex/releases/latest/download/%s " \\
  busytex\_pipeline.js busytex\_worker.js \\
  busytex.wasm busytex.js \\
  texlive-basic.js texlive-basic.data \\
  ubuntu-texlive-latex-extra.data ubuntu-texlive-latex-extra.js \\
  ubuntu-texlive-latex-recommended.data ubuntu-texlive-latex-recommended.js \\
  ubuntu-texlive-science.data ubuntu-texlive-science.js)

python3 example/example.py
```

Then open http://localhost:8080/example/example.html.

### Native

```shell
sh example/example.sh
```

### TeX Live 2026 ISO

```shell
wget http://mirrors.ctan.org/systems/texlive/Images/texlive2026.iso
split -b2G -d texlive2026.iso texlive2026.iso.
```

## Building from source

### Prerequisites

```shell
apt-get install -y \\
  libnsl-dev build-essential coreutils cmake bash git \\
  xz-utils wget perl gperf p7zip-full python3 gh strace \\
  libarchive-tools curl dos2unix bubblewrap texlive-binaries
```

### Emscripten

```shell
git clone https://github.com/emscripten-core/emsdk
cd emsdk
./emsdk update-tags
./emsdk install tot
./emsdk activate tot
source emsdk\_env.sh
cd ..
```

### Build

```shell
git clone https://github.com/TeXlyre/texlyre-busytex-build
cd texlyre-busytex-build

export MAKEFLAGS=-j8

# Fetch and patch TeX Live sources
make source/texlive.txt build/versions.txt

# Native tools and binaries
make native

# Smoke test
make smoke-native

# TeX Live tree
make source/texmfrepo.txt
make build/texlive-basic.txt build/texlive-extra.txt build/texlive-full.txt

# WASM build
make wasm

# End-to-end example
sh example/example.sh

# TeX Live data packages
make build/wasm/texlive-basic.js
make build/wasm/texlive-extra.js

# Post-Process WASM hyphenation and XeTeX patch
make wasm-postbuild-hyphenation-fmt

# Distribution bundles
make dist-native dist-wasm
```

### Clean

```shell
rm source/texlive.patched
make clean
```

## TeX Live package server

For packages not shipped in `texlive-basic` or `texlive-extra`, run a server that streams them on demand. The remote endpoint is configurable via the `compile()` method in `web/busytex\_pipeline.js`.

Build the full TeX Live tree first:

```shell
make -B build/texlive-full.txt
make build/wasm/busytex.js
```

Then either run a [production server](./texlive-server/README.md) or the development server described in that same README.

## Running the demo

```shell
python3 example/example.py --port 8183
```

Open http://localhost:8183/example/example.html. To test a freshly built WASM bundle, copy `./dist-wasm/\*` to `./dist/`.

## Roadmap

* mf-nowin
* LuaMetaTeX / LMTX (lua)
* tlmgr (perl)
* Biber (perl)
* mktexlsr, fmtutil, updmap (perl)

## Help wanted

* Single-page HTML5 offline webapp ([html5doctor](https://diveinto.html5doctor.com/offline.html))
* Refactor Emscripten data-packages subsystem ([issue #14385](https://github.com/emscripten-core/emscripten/issues/14385))
* LLVM localize-globals in WASM objects ([bug 51279](https://bugs.llvm.org/show_bug.cgi?id=51279))
* Upstream build-sequence changes to TeX Live ([tlbuild thread](https://tug.org/pipermail/tlbuild/2021q1/004806.html))
* Assorted Emscripten improvements ([#12093](https://github.com/emscripten-core/emscripten/issues/12093), [#12256](https://github.com/emscripten-core/emscripten/issues/12256), [#13466](https://github.com/emscripten-core/emscripten/issues/13466), [#13219](https://github.com/emscripten-core/emscripten/issues/13219))
* Better WASM init error surfacing ([#14777](https://github.com/emscripten-core/emscripten/issues/14777))
* Explore `DLLPROC` as an alternative to redefining `main` symbols
* Biber on WASM ([biber #338](https://github.com/plk/biber/issues/338), [buildbiber](https://github.com/busytex/buildbiber))
* Audit shipped TeX Live packages to reduce footprint (fonts, fontmaps, hyphenation)
* Binary size reduction / stripping
* Build x86\_64-linux-glibc with clang to match the WASM toolchain
* GitHub Actions test for x86\_64 binaries on WSLv1
* Trim Makefile build sequence
* Node.js tests for WASM binaries and data-package preloading
* Preloaded single-file, single-engine minimal builds (WASM + native) with basic LaTeX
* Virtual / `LD\_PRELOAD`-based filesystems to avoid ISO/ZIP unpacking and embed TeX packages in native builds
* Static Perl embedding for `fmtutil.pl`, `updmap.pl` ([perlembed](https://perldoc.perl.org/perlembed), [extending/embedding guide](http://www.kaiyuanba.cn/content/develop/Perl/Extending_And_Embedding_Perl.pdf))
* Pre-parse `ProvidesPackage` metadata for data packages

## References

* [busytex (pdftex and xetex) TL2025 update](https://github.com/SiglumProject/busytex)
* [pdftex.js](https://github.com/dmonad/pdftex.js)
* [xetex.js](https://github.com/lyze/xetex-js)
* [texlive.js](https://github.com/manuels/texlive.js/)
* [latexjs](https://github.com/latexjs/latexjs)
* [dvi2html](https://github.com/kisonecat/dvi2html), [web2js](https://github.com/kisonecat/web2js)
* [SwiftLaTeX](https://github.com/SwiftLaTeX/SwiftLaTeX)
* [JavascriptSubtitlesOctopus](https://github.com/Dador/JavascriptSubtitlesOctopus)
* [js-sha1](https://raw.githubusercontent.com/emn178/js-sha1)
* [BLFS TeX Live](http://www.linuxfromscratch.org/blfs/view/svn/pst/texlive.html)
* latexmk: [CTAN](https://ctan.org/tex-archive/support/latexmk), [docs](https://mg.readthedocs.io/latexmk.html), [latexmk.py](https://github.com/schlamar/latexmk.py), [fork](https://github.com/JanKanis/latexmk.py), [PR #11](https://github.com/schlamar/latexmk.py/pull/11)
* [TeX::AutoTeX::File](https://metacpan.org/release/TSCHWAND/TeX-AutoTeX-v0.906.0/view/lib/TeX/AutoTeX/File.pm)
