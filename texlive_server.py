#!/usr/bin/env python3
"""
Serves files from a TeX Live texmf-dist tree for on-the-fly package fetching.

Usage:
    python3 texlive_server.py --texmf /path/to/texlive-full/texmf-dist --port 8070

Requests: GET /<format>/<filename>
Returns 200 with file contents, or 404.
"""

import os
import sys
import argparse
import http.server
import urllib.parse
import functools

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


def build_index(texmf_root):
    index = {}
    for dirpath, _, filenames in os.walk(texmf_root):
        for fname in filenames:
            key = fname.lower()
            if key not in index:
                index[key] = os.path.join(dirpath, fname)
    return index


class TexLiveHandler(http.server.BaseHTTPRequestHandler):
    def __init__(self, file_index, texmf_root, *args, **kwargs):
        self.file_index = file_index
        self.texmf_root = texmf_root
        super().__init__(*args, **kwargs)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        parts = parsed.path.strip('/').split('/', 1)

        if len(parts) != 2:
            self.send_error(400, 'Expected /<format>/<filename>')
            return

        try:
            fmt = int(parts[0])
        except ValueError:
            self.send_error(400, 'Format must be integer')
            return

        raw_name = urllib.parse.unquote(parts[1])
        filepath = self._find_file(raw_name, fmt)

        if filepath is None:
            self.send_error(404, f'{raw_name} not found')
            return

        try:
            with open(filepath, 'rb') as f:
                data = f.read()
        except OSError:
            self.send_error(500, 'Read error')
            return

        self.send_response(200)
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(data)

    def _find_file(self, name, fmt):
        key = name.lower()
        result = self.file_index.get(key)
        if result:
            return result

        extensions = KPSE_EXTENSIONS.get(fmt, [])
        for ext in extensions:
            if not key.endswith(ext):
                result = self.file_index.get(key + ext)
                if result:
                    return result
        return None

    def log_message(self, format, *args):
        status = args[1] if len(args) > 1 else ''
        sys.stderr.write(f'[texlive_server] {args[0]} -> {status}\n')


def main():
    parser = argparse.ArgumentParser(description='TeX Live remote file server')
    parser.add_argument('--texmf', default='build/texlive-full/texmf-dist', help='Path to texmf-dist root')
    parser.add_argument('--port', type=int, default=8070)
    parser.add_argument('--bind', default='0.0.0.0')
    args = parser.parse_args()

    if not os.path.isdir(args.texmf):
        print(f'Error: {args.texmf} is not a directory', file=sys.stderr)
        sys.exit(1)

    print(f'Indexing {args.texmf} ...', file=sys.stderr)
    file_index = build_index(args.texmf)
    print(f'Indexed {len(file_index)} files', file=sys.stderr)

    handler = functools.partial(TexLiveHandler, file_index, args.texmf)
    server = http.server.HTTPServer((args.bind, args.port), handler)
    print(f'Serving on http://{args.bind}:{args.port}/', file=sys.stderr)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down', file=sys.stderr)
        server.server_close()


if __name__ == '__main__':
    main()
