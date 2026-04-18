mergeInto(LibraryManager.library, {
    $KPSE_REMOTE__postset: 'KPSE_REMOTE.init();',
    $KPSE_REMOTE: {
        dir: '/tmp/texlive_remote',
        hits: null,
        misses: null,
        init: function () {
            Module['kpse_remote_register'] = function (name, format, contents) {
                return KPSE_REMOTE.register(name, format, contents);
            };
            Module['kpse_remote_has'] = function (name, format) {
                KPSE_REMOTE.ensure();
                return (format + '/' + name) in KPSE_REMOTE.hits;
            };
            Module['kpse_remote_clear'] = function () {
                KPSE_REMOTE.hits = {};
                KPSE_REMOTE.misses = {};
            };
        },
        ensure: function () {
            if (KPSE_REMOTE.hits === null) KPSE_REMOTE.hits = {};
            if (KPSE_REMOTE.misses === null) KPSE_REMOTE.misses = {};
            try { FS.stat(KPSE_REMOTE.dir); } catch (e) { try { FS.mkdir(KPSE_REMOTE.dir); } catch (e2) { } }
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
        lookup: function (name, format) {
            KPSE_REMOTE.ensure();
            var key = format + '/' + name;
            if (key in KPSE_REMOTE.misses) return null;
            if (key in KPSE_REMOTE.hits) return KPSE_REMOTE.hits[key];
            var savepath = KPSE_REMOTE.pathFor(name, format);
            try { FS.stat(savepath); KPSE_REMOTE.hits[key] = savepath; return savepath; } catch (e) { }
            return null;
        },
        fetch: function (name, format) {
            var endpoint = Module.ENV['TEXLIVE_REMOTE_ENDPOINT'];
            if (!endpoint) { KPSE_REMOTE.misses[format + '/' + name] = 1; return null; }
            var url = endpoint + (endpoint.endsWith('/') ? '' : '/') + format + '/' + encodeURIComponent(name);
            var xhr = new XMLHttpRequest();
            xhr.open('GET', url, false);
            xhr.timeout = 30000;
            xhr.responseType = 'arraybuffer';
            try { xhr.send(); } catch (e) { KPSE_REMOTE.misses[format + '/' + name] = 1; return null; }
            if (xhr.status !== 200 || !xhr.response || xhr.response.byteLength === 0) {
                KPSE_REMOTE.misses[format + '/' + name] = 1;
                return null;
            }
            return KPSE_REMOTE.register(name, format, new Uint8Array(xhr.response));
        }
    },
    kpse_remote_fetch_js__deps: ['$UTF8ToString', '$stringToNewUTF8', '$KPSE_REMOTE'],
    kpse_remote_fetch_js: function (namePtr, format) {
        var name = UTF8ToString(namePtr);
        if (!name || name.indexOf('/') !== -1 || name.length > 255) return 0;
        var hit = KPSE_REMOTE.lookup(name, format);
        if (hit) return stringToNewUTF8(hit);
        var fetched = KPSE_REMOTE.fetch(name, format);
        return fetched ? stringToNewUTF8(fetched) : 0;
    }
});
