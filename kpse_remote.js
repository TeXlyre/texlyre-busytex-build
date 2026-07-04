mergeInto(LibraryManager.library, {
    $KPSE_REMOTE__postset: 'KPSE_REMOTE.init();',
    $KPSE_REMOTE: {
        dir: '/tmp/texlive_remote',
        missesFile: '/tmp/texlive_remote/.misses.json',
        hits: null,
        misses: null,
        manifestLoaded: false,
        shellHandlers: (typeof globalThis !== 'undefined' && globalThis.__busytex_shell_handlers) || {},
        init: function () {
            if (typeof globalThis !== 'undefined')
                globalThis.__busytex_shell_handlers = KPSE_REMOTE.shellHandlers;

            Module['kpse_remote_register'] = function (name, format, contents) {
                return KPSE_REMOTE.register(name, format, contents);
            };
            Module['kpse_remote_register_misses'] = function (keys) {
                return KPSE_REMOTE.registerMisses(keys);
            };
            Module['kpse_remote_has'] = function (name, format) {
                KPSE_REMOTE.ensure();
                return (format + '/' + name) in KPSE_REMOTE.hits;
            };
            Module['kpse_remote_clear'] = function () {
                KPSE_REMOTE.hits = {};
                KPSE_REMOTE.misses = {};
                KPSE_REMOTE.manifestLoaded = false;
            };
            Module['kpse_remote_reload_manifest'] = function () {
                KPSE_REMOTE.manifestLoaded = false;
                KPSE_REMOTE.ensure();
            };

            var scope = typeof self !== 'undefined' ? self : globalThis;
            scope.register_shell_handler = function (command, handler) {
                KPSE_REMOTE.shellHandlers[command] = handler;
            };
            scope.unregister_shell_handler = function (command) {
                delete KPSE_REMOTE.shellHandlers[command];
            };
            scope.list_shell_handlers = function () {
                return Object.keys(KPSE_REMOTE.shellHandlers);
            };
        },
        ensure: function () {
            if (KPSE_REMOTE.hits === null) KPSE_REMOTE.hits = {};
            if (KPSE_REMOTE.misses === null) KPSE_REMOTE.misses = {};
            try { FS.stat(KPSE_REMOTE.dir); } catch (e) { try { FS.mkdir(KPSE_REMOTE.dir); } catch (e2) { } }
            if (!KPSE_REMOTE.manifestLoaded) {
                KPSE_REMOTE.manifestLoaded = true;
                try {
                    var raw = FS.readFile(KPSE_REMOTE.missesFile, { encoding: 'utf8' });
                    var keys = JSON.parse(raw);
                    if (Array.isArray(keys))
                        for (var i = 0; i < keys.length; i++) KPSE_REMOTE.misses[keys[i]] = 1;
                } catch (e) { }
            }
        },
        pathFor: function (name, format) {
            var safe = name.replace(/[^a-zA-Z0-9._-]/g, '_');
            return KPSE_REMOTE.dir + '/' + format + '_' + safe;
        },
        register: function (name, format, contents) {
            KPSE_REMOTE.ensure();
            var savepath = KPSE_REMOTE.pathFor(name, format);
            FS.writeFile(savepath, contents);
            KPSE_REMOTE.hits[format + '/' + name] = savepath;
            delete KPSE_REMOTE.misses[format + '/' + name];
            return savepath;
        },
        registerMisses: function (keys) {
            KPSE_REMOTE.ensure();
            if (Array.isArray(keys))
                for (var i = 0; i < keys.length; i++) KPSE_REMOTE.misses[keys[i]] = 1;
            var merged = Object.keys(KPSE_REMOTE.misses);
            try { FS.writeFile(KPSE_REMOTE.missesFile, JSON.stringify(merged)); } catch (e) { }
        },
        lookup: function (name, format) {
            KPSE_REMOTE.ensure();
            var key = format + '/' + name;
            if (key in KPSE_REMOTE.hits) return KPSE_REMOTE.hits[key];
            var savepath = KPSE_REMOTE.pathFor(name, format);
            try { FS.stat(savepath); KPSE_REMOTE.hits[key] = savepath; return savepath; } catch (e) { }
            return null;
        },
        isMiss: function (name, format) {
            KPSE_REMOTE.ensure();
            return (format + '/' + name) in KPSE_REMOTE.misses;
        },
        fetch: function (name, format) {
            var endpoint = Module.ENV['TEXLIVE_REMOTE_ENDPOINT'];
            if (!endpoint) return null;
            var url = endpoint + (endpoint.endsWith('/') ? '' : '/') + format + '/' + encodeURIComponent(name);
            var xhr = new XMLHttpRequest();
            xhr.open('GET', url, false);
            xhr.timeout = 30000;
            xhr.responseType = 'arraybuffer';
            try { xhr.send(); } catch (e) { return null; }
            if (xhr.status === 200 && xhr.response && xhr.response.byteLength > 0)
                return KPSE_REMOTE.register(name, format, new Uint8Array(xhr.response));
            if (xhr.status === 404) KPSE_REMOTE.misses[format + '/' + name] = 1;
            return null;
        },
        parseArgv: function (cmd) {
            var argv = [];
            var re = /"([^"]*)"|'([^']*)'|([^\s]+)/g;
            var match;
            while ((match = re.exec(cmd)) !== null)
                argv.push(match[1] || match[2] || match[3]);
            return argv;
        },
        shellDispatch: function (cmd, cwd) {
            if (!cmd)
                return -1;

            var argv = KPSE_REMOTE.parseArgv(cmd);
            if (!argv.length)
                return -1;

            var handler = KPSE_REMOTE.shellHandlers[argv[0]];
            if (!handler)
                return -1;

            try {
                var result = handler(argv, cwd, FS, PATH, Module);
                if (result && Array.isArray(result.files)) {
                    for (var i = 0; i < result.files.length; i++) {
                        var file = result.files[i];
                        FS.writeFile(file.path, file.contents);
                    }
                }
                return result && typeof result.exit_code === 'number' ? result.exit_code : 0;
            }
            catch (e) {
                if (Module.printErr)
                    Module.printErr('shell handler failed: ' + e);
                return 1;
            }
        }
    },
    kpse_remote_fetch_js__deps: ['$UTF8ToString', '$stringToNewUTF8', '$KPSE_REMOTE'],
    kpse_remote_fetch_js: function (namePtr, format) {
        var name = UTF8ToString(namePtr);
        if (!name || name.indexOf('/') !== -1 || name.length > 255) return 0;
        var hit = KPSE_REMOTE.lookup(name, format);
        if (hit) return stringToNewUTF8(hit);
        if (KPSE_REMOTE.isMiss(name, format)) return 0;
        var fetched = KPSE_REMOTE.fetch(name, format);
        if (!fetched && format === 39 && name.indexOf('.') !== -1) {
            var moduleName = name.split('.').pop();
            hit = KPSE_REMOTE.lookup(moduleName, format);
            if (hit) return stringToNewUTF8(hit);
            if (!KPSE_REMOTE.isMiss(moduleName, format))
                fetched = KPSE_REMOTE.fetch(moduleName, format);
        }
        return fetched ? stringToNewUTF8(fetched) : 0;
    },
    shell_escape_dispatch_js__deps: ['$UTF8ToString', '$KPSE_REMOTE'],
    shell_escape_dispatch_js: function (cmdPtr, cwdPtr) {
        return KPSE_REMOTE.shellDispatch(UTF8ToString(cmdPtr), UTF8ToString(cwdPtr));
    }
});