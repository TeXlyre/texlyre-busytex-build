// Replaces emperl's nodeperl_dev_prerun.js, which requires('path') and mounts
// NODEFS at the build-time prefix. Here the prefix is preloaded into MEMFS at
// link time, so the module runs unchanged under a browser, a worker and node.

Module.thisProgram = '/opt/perl-wasm/bin/biber';

Module.preRun = (Module.preRun || []).concat([
    function () {
        FS.mkdirTree('/home/web_user/biber');
        FS.chdir('/home/web_user/biber');
    },
    function () {
        const perl_main = Module._main;
        Module._main = function () {
            perl_main.apply(this, arguments);
            return Module.ccall('emperl_end_perl', 'number', [], []);
        };
    }
]);
