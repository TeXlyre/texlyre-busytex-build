(function () {
    if (typeof BusytexPipeline === 'undefined' || BusytexPipeline.__shell_escape_patched)
        return;

    const original = BusytexPipeline.prototype.compile;
    let source = original.toString();

    source = source.replace(
        "async compile(files, main_tex_path, bibtex, makeindex = null, rerun = null, verbose, driver, data_packages_js = [], remote_endpoint = '') {",
        "async function compile(files, main_tex_path, bibtex, makeindex = null, rerun = null, verbose, driver, data_packages_js = [], remote_endpoint = '', shell_escape = false) {"
    );
    source = source.replace(
        "const verbose_args_for = key => (this.verbose_args[verbose] || this.verbose_args[BusytexPipeline.VerboseSilent])[key];",
        "const verbose_args_for = key => (this.verbose_args[verbose] || this.verbose_args[BusytexPipeline.VerboseSilent])[key];\n\n        const shell_escape_args = shell_escape ? ['--shell-escape'] : ['--no-shell-escape'];"
    );
    source = source.replaceAll("'--no-shell-escape'", "...shell_escape_args");

    if (source === original.toString())
        throw new Error('Failed to patch BusytexPipeline shell escape support');

    BusytexPipeline.prototype.compile = (0, eval)('(' + source + ')');
    BusytexPipeline.__shell_escape_patched = true;
})();
