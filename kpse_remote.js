mergeInto(LibraryManager.library, {
    kpse_remote_fetch_js__deps: ['$UTF8ToString', '$stringToNewUTF8'],
    kpse_remote_fetch_js: function (namePtr, format) {
        var name = UTF8ToString(namePtr);
        if (!name || name.indexOf('/') !== -1 || name.length > 255)
            return 0;

        var endpoint = Module.ENV['TEXLIVE_REMOTE_ENDPOINT'];
        if (!endpoint)
            return 0;

        var cacheKey = format + '/' + name;

        if (!Module._kpse_remote_cache_404)
            Module._kpse_remote_cache_404 = {};
        if (!Module._kpse_remote_cache_200)
            Module._kpse_remote_cache_200 = {};

        if (cacheKey in Module._kpse_remote_cache_404)
            return 0;

        if (cacheKey in Module._kpse_remote_cache_200) {
            var cached = Module._kpse_remote_cache_200[cacheKey];
            return stringToNewUTF8(cached);
        }

        var url = endpoint;
        if (!url.endsWith('/')) url += '/';
        url += format + '/' + encodeURIComponent(name);

        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, false);
        xhr.timeout = 30000;
        xhr.responseType = 'arraybuffer';

        try {
            xhr.send();
        } catch (e) {
            Module._kpse_remote_cache_404[cacheKey] = 1;
            return 0;
        }

        if (xhr.status === 200 && xhr.response && xhr.response.byteLength > 0) {
            var data = new Uint8Array(xhr.response);
            var savedir = '/tmp/texlive_remote';
            try { FS.mkdir(savedir); } catch (e) { }

            var safeName = name.replace(/[^a-zA-Z0-9._-]/g, '_');
            var savepath = savedir + '/' + format + '_' + safeName;

            try {
                FS.writeFile(savepath, data);
            } catch (e) {
                Module._kpse_remote_cache_404[cacheKey] = 1;
                return 0;
            }

            Module._kpse_remote_cache_200[cacheKey] = savepath;
            return stringToNewUTF8(savepath);
        }

        Module._kpse_remote_cache_404[cacheKey] = 1;
        return 0;
    }
});