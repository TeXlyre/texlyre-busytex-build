mergeInto(LibraryManager.library, {
    $KPSE_REMOTE__postset: 'KPSE_REMOTE.init();',
    $KPSE_REMOTE: {
        dir: '/tmp/texlive_remote',
        missesFile: '/tmp/texlive_remote/.misses.json',
        hits: null,
        misses: null,
        manifestLoaded: false,
        init: function () {
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
        return fetched ? stringToNewUTF8(fetched) : 0;
    }
});