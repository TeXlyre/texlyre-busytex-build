import os
import functools
from flask import Flask, send_file, make_response
from flask_cors import CORS, cross_origin
import redis as redis_lib
import re

app = Flask(__name__)
redis_client = None

api_origins = os.environ.get('API_ORIGINS', '')
if api_origins == '*':
    CORS(app)
elif api_origins:
    CORS(app, resources={r"/*": {"origins": [o.strip() for o in api_origins.split(',')]}})

KPSE_EXTENSIONS = {
    3:  ['.tfm'],
    4:  ['.afm'],
    6:  ['.bib'],
    7:  ['.bst'],
    10: ['.fmt'],
    11: ['.map'],
    26: ['.tex', '.sty', '.cls', '.fd', '.def', '.cfg', '.ltx', '.dtx', '.ldf', '.clo', '.bbx', '.cbx', '.lbx', '.dbx'],
    32: ['.pfa', '.pfb'],
    33: ['.vf'],
    35: ['.ttf', '.ttc'],
    43: ['.enc'],
    44: ['.cmap'],
    46: ['.otf'],
    39: ['.lua'],
}

_SAFE_NAME = re.compile(r'[^a-zA-Z0-9._-]')
_file_index = {}


def init_redis(redis_url):
    global redis_client
    try:
        redis_client = redis_lib.from_url(redis_url)
        app.logger.info(f'Redis initialized: {redis_url}')
    except Exception as e:
        app.logger.error(f'Redis init failed: {e}')
        redis_client = None


def build_index(texmf_root):
    index = {}
    for dirpath, _, filenames in os.walk(texmf_root):
        for fname in filenames:
            key = fname.lower()
            if key not in index:
                index[key] = os.path.join(dirpath, fname)
    return index


def get_index():
    global _file_index
    if not _file_index:
        texmf_root = os.path.abspath(os.environ.get('TEXMF_ROOT', '../build/texlive-full/texmf-dist'))
        if os.path.isdir(texmf_root):
            app.logger.info(f'Indexing {texmf_root}')
            _file_index = build_index(texmf_root)
            app.logger.info(f'Indexed {len(_file_index)} files')
        else:
            app.logger.warning(f'TEXMF_ROOT not found: {texmf_root}')
    return _file_index


def find_file(name, fmt):
    cached = None
    cache_key = f'{fmt}:{name}'

    if redis_client:
        try:
            cached = redis_client.get(cache_key)
            if cached:
                path = cached.decode()
                if os.path.isfile(path):
                    return path
        except Exception:
            pass

    index = get_index()
    key = name.lower()
    result = index.get(key)

    if result is None:
        for ext in KPSE_EXTENSIONS.get(fmt, []):
            if not key.endswith(ext):
                result = index.get(key + ext)
                if result:
                    break

    if result and redis_client:
        try:
            redis_client.setex(cache_key, 86400, result)
        except Exception:
            pass

    return result


@app.route('/<int:fileformat>/<filename>')
@cross_origin()
def fetch_file(fileformat, filename):
    filename = _SAFE_NAME.sub('', filename)
    if not filename:
        return 'Bad request', 400

    filepath = find_file(filename, fileformat)
    if filepath is None:
        return 'File not found', 301

    response = make_response(send_file(filepath, mimetype='application/octet-stream'))
    response.headers['fileid'] = os.path.basename(filepath)
    response.headers['Access-Control-Expose-Headers'] = 'fileid'
    return response