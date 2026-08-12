// Loader for the standalone biber wasm module.
//
// biber is a perl interpreter with its XS dependencies statically linked, so it
// cannot share busytex's main(). It is loaded lazily on the first .bcf run and
// exchanges files with the busytex module through the caller, which copies the
// .bcf and .bib in and the .bbl out.

export class BusytexBiber {
    constructor(biber_js, biber_wasm, print, script_loader) {
        this.biber_js = biber_js;
        this.biber_wasm = biber_wasm;
        this.print = print;
        this.script_loader = script_loader;
        this.Module = null;
        this.work_dir = '/home/web_user/biber';
        this.prefix = '/opt/perl-wasm';
    }

    async initialize() {
        if (this.Module)
            return this.Module;

        const Module = {
            noInitialRun: true,
            thisProgram: 'biber',
            locateFile: path => path.endsWith('.wasm') ? this.biber_wasm : path,
            print: text => this.print(text),
            printErr: text => this.print(text),
        };

        await this.script_loader(this.biber_js, Module);
        await new Promise(resolve => { Module.onRuntimeInitialized = resolve; });

        Module.FS.mkdirTree(this.work_dir);
        Module.FS.chdir(this.work_dir);

        this.Module = Module;
        return Module;
    }

    // files: [{path, contents}] written next to the .bcf, since biber resolves
    // data sources relative to the control file. Returns the .bbl text, or null
    // when biber exited non-zero.
    async run(bcf_path, files, verbose_args = []) {
        const Module = await this.initialize();
        const { FS, PATH } = Module;

        for (const { path, contents } of files) {
            const full = PATH.join(this.work_dir, PATH.basename(path));
            FS.writeFile(full, contents);
        }

        const bcf = PATH.basename(bcf_path);
        const bbl = bcf.replace(/\.bcf$/, '.bbl');
        const argv = ['biber', '--output-format=bbl', `--outfile=${bbl}`, '--nolog', ...verbose_args, bcf];

        this.print('$ ' + argv.join(' '));

        let exit_code = 0;
        try {
            exit_code = Module.callMain(argv.slice(1));
        } catch (err) {
            exit_code = typeof err.status == 'number' ? err.status : 1;
        }

        if (exit_code != 0)
            return null;

        const bbl_full = PATH.join(this.work_dir, bbl);
        return FS.analyzePath(bbl_full).exists ? FS.readFile(bbl_full, { encoding: 'utf8' }) : null;
    }

    reset() {
        this.Module = null;
    }
}
