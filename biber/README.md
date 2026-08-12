# biber for WebAssembly

Builds biber as a standalone wasm module: a perl interpreter with all of biber's
XS dependencies statically linked, loaded on demand by the pipeline when a `.bcf`
appears. It is not linked into `busytex` — it cannot share the web2c
multiplexer's `main()`, it is roughly 8 MB, and almost no compilation needs it.

    make wasm-biber                                  # build locally
    make URLRELEASE=<release-url> download-biber-wasm # or fetch a published build

CI runs it as its own job, `.github/workflows/build-biber-wasm.yml`, which
publishes `biber.js` and `biber.wasm` as a release. `build-wasm.yml` takes a new
optional `biberwasmreleasetag` input and downloads that artifact rather than
rebuilding it, since the job compiles perl twice and biber changes rarely.
Leaving the input empty ships a bundle without biber; the `dist-wasm` copies are
prefixed with `-`, so nothing fails.

## Layout

    biber/
      build_biber.sh            top-level driver
      build_deps.sh             libxml2, sombok, btparse
      build_xs.sh               generic out-of-tree XS builder
      config_fixups.sh          corrections to perl's config.sh
      emcc_configure_shim.sh    emcc wrapper used while Configure runs
      fetch_sources.sh          CPAN/upstream source fetch
      modules.txt               XS module manifest with versions
      patches/                  perl core patches, against perl 5.38.2
    web/
      busytex_biber.js          browser-side loader

## Dependency shape

The XS set was determined by instrumenting a real biber run and reading
`@DynaLoader::dl_shared_objects`. Tool mode and a `.bcf` run load an identical
set of 40 shared objects — 19 core, 21 CPAN — so the closure is complete.

Of the 21 CPAN modules only three link an external C library:

| module | library | note |
| --- | --- | --- |
| Text::BibTeX | libbtparse | bundled in the dist, 22 `.c` files |
| Unicode::LineBreak | libsombok | bundled; libthai omitted |
| XML::LibXML | libxml2 | the only genuinely external one |

The other eighteen are self-contained. `Storable` must be added to `static_ext`:
WebPerl omits it and biber requires it.

## Why modules are built out of tree

Dropping a dist into perl's `cpan/` makes the perl build run its `Makefile.PL`
under **miniperl**, which cannot load the XS `IO::File` that `inc::latest` and
Module::Build need. `build_xs.sh` instead generates the `.c` with a host xsubpp,
compiles it with emcc against the target `CORE` headers, and archives it to
`lib/auto/<Path>/<Leaf>.a` where `static_ext` expects it.

## Non-obvious failures this build works around

- **emcc >= 2.0 makes implicit declarations an error.** Configure reports
  `setproctitle`, `setruid`, `setrgid`, `fdclose`, `malloc_size` and
  `malloc_good_size` as present because emcc tolerates undefined symbols at link
  time, but the sysroot headers never declare them. See `config_fixups.sh`.
- **The INF/NAN probes return the literal string `undef`**, which perl emits as
  `#define DOUBLEINFBYTES undef`. Configure does get `doublekind=3` and
  `longdblkind=1` right, so the standard IEEE patterns are supplied directly.
- **`make -j` races** on the `generate_uudmap` rule. Serial only.
- **Configure executes its test programs**, and emcc 3.x no longer emits a node
  shebang or the executable bit for extensionless output. Hence the shim, which
  also forces `SINGLE_FILE` because node >= 18 has a global `fetch` that sends
  emscripten's loader down the browser path.
- **`Configure -S` regenerates `Makefile` from `Makefile.SH`**, so the link-rule
  change is a patch against the `.SH`.
- **`perlmain.c` is not regenerated when `static_ext` changes** — remove it.
- **Version stamps matter.** `-DVERSION`/`-DXS_VERSION` must match the `.pm` or
  the bootstrap fails with `object version 0 does not match bootstrap parameter`.
- **Two symbol collisions.** `PerlIO::utf8_strict` defines
  `PerlIOBase_flush_linebuf`, already in core; and XML::LibXML's `dom.o`,
  `xpath.o` and friends collide by member name with libxml2's, so `ar` silently
  replaces them and the link fails on `domXPathFind`. Members are prefixed on
  merge.
- **Perl < 5.32 miscompiles under gcc >= 13 at -O2** — miniperl segfaults in
  `buildcustomize`. The host build is pinned to `-O0`.

## Perl version

The series in `patches/` targets **perl 5.38.2** and applies clean to a pristine
tree, because biber's `Build.PL` requires 5.32.0 and WebPerl's newest branch is
5.30.0. It is the upstream emperl series forward-ported: the Configure
`--sysroot` fix is already upstream and dropped, `02-disable-signal-handling`
was hand-ported (its sites moved, and the `!defined(PERL_MICRO)` guard is gone
since 5.36), the single-stage link is folded into `04-makefile-sh`, and the
hints file now derives the sysroot from `emcc --cflags` instead of the removed
`$EMSCRIPTEN` variable.

The version matters for output, not just for `Build.PL`. Built against 5.30 a
`.bcf` run differs from native biber in 48 of ~2900 lines — all `sortinithash`
values and NFD normalization — because 5.30 ships Unicode::Collate 1.27 with UCA
data 10.0.0 against 5.38's 1.31 and 13.0.0. Nothing to do with wasm.

## Sources

Everything is fetched from CPAN and upstream, not `apt-get source`: GitHub's
Ubuntu images ship with `deb-src` disabled. CPAN dists are resolved through
`fastapi.metacpan.org/v1/download_url/<Module>?version===<ver>`, the same trick
`build-biber.yml` already uses, so no author ids are pinned in `modules.txt`.

## Measured

Perl 5.30.0 + 41 static extensions runs biber 2.19 to completion on biblatex's
`general.bcf`: 60 entries, 91,889-byte `.bbl`, 4.2 s against 1.3 s native.
