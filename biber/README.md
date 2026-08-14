# Biber

biber compiled into a standalone WebAssembly module: a perl interpreter with every XS dependency statically linked, loaded on demand by `busytex_pipeline.js` when a `.bcf` is produced.

It is not linked into `busytex`. It cannot share the web2c multiplexer's `main()`, it is roughly 8 MB, and almost no compilation needs it.

**Bundled:** perl 5.38.2 (patched for emscripten), biber 2.22, 20 CPAN XS modules, libxml2, sombok, btparse.

---

## Usage

**Using prebuilt assets:**

```shell
make URLRELEASE=https://github.com/TeXlyre/texlyre-busytex-build/releases/latest/download download-biber-wasm
```

**Using a local build:**

```shell
apt-get install -y build-essential curl xz-utils autoconf automake libtool pkg-config biber
make wasm-biber
```

The `biber` package supplies the pure-perl dependency closure, already resolved, from `/usr/share/perl5`.

Output is `build/wasm/biber.js`, `build/wasm/biber.wasm` and `build/wasm/biber.data`, copied into `dist-wasm/` by `make dist-wasm`. The interpreter bakes its prefix into `@INC`, so it is configured against `/opt/perl-wasm` and the perl tree is preloaded into the module at that path; the directory must exist and be writable on the build host.

CI builds it as its own job, `.github/workflows/build-biber-wasm.yml`, and publishes a release. `build-wasm.yml` takes an optional `biberwasmreleasetag` input and downloads that artifact rather than rebuilding it; left empty, the bundle ships without biber.

---

## Layout

```
fetch_sources.sh          perl, biber, CPAN dists, libxml2, sombok
build_deps.sh             libxml2, sombok, btparse
build_xs.sh               one CPAN XS module -> lib/auto/<Path>/<Leaf>.a
config_fixups.sh          corrections to perl's config.sh
emcc_configure_shim.sh    emcc wrapper used while Configure runs
modules.txt               XS module manifest with versions
patches/                  perl core patches, against 5.38.2
build_biber.sh            driver
```

XS modules are built out of tree rather than dropped into perl's `cpan/`, which would make the perl build run their `Makefile.PL` under miniperl — miniperl cannot load the XS `IO::File` that `inc::latest` and Module::Build need. `build_xs.sh` generates the `.c` with a host xsubpp, compiles it against the target `CORE` headers, and archives it where `static_ext` expects it.

## Versions

`PERL_VERSION_BIBER` and `BIBER_VERSION` in the Makefile. Changing the perl version may require rebasing `patches/`.

Building against perl < 5.32 produces subtly different output: `sortinithash` values and NFD normalization differ from native biber, because the bundled Unicode::Collate carries older UCA data.
