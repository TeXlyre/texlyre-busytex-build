# Texlive Server

Serves TeXLive 2026 files on demand for use with [busytex](https://github.com/busytex/busytex).

Implements the endpoint contract expected by `TEXLIVE_REMOTE_ENDPOINT` in `busytex_pipeline.js`:
```
GET /<format_id>/<filename>
```

Returns raw file bytes with a `fileid` response header, or HTTP 301 if not found.

## Requirements

- A TeXLive 2026 `texmf-dist` tree on disk (from `make build/texlive-full.txt` in the busytex repo, or extracted from the ISO)
- Set `TEXMF_ROOT` to the path of that tree

## Running locally (bare metal)
```bash
pip install -r requirements.txt
TEXMF_ROOT=../build/texlive-full/texmf-dist PORT=8070 python3 wsgi.py
```

With Redis caching:
```bash
REDIS_URL=redis://localhost:6379 TEXMF_ROOT=../build/texlive-full/texmf-dist python3 wsgi.py
```

## Running with Docker
```bash
cp envfile .env
# Set TEXMF_ROOT in .env to the host path of your texmf-dist tree
docker compose build
docker compose up
```

## Deployment with Cloudflare Tunnel

1. Create a Cloudflare account and add your domain.
2. Get the Global API token from Cloudflare.
3. Copy `envfile` to `.env` and fill in `CLOUDFLARE_API_KEY`, `HOST_DOMAIN`, and `TEXMF_ROOT`.
4. Build and start:
```bash
docker compose -f docker-compose.cloudflare.yml build
docker compose -f docker-compose.cloudflare.yml up -d
chmod +x ./scripts/run_texlive_cloudflare_tunnel.sh
source ./.env && ./scripts/run_texlive_cloudflare_tunnel.sh "${CLOUDFLARE_API_KEY}" "${HOST_DOMAIN}" "${PORT}"
```

Stop with:
```bash
docker compose -f docker-compose.cloudflare.yml down
```

On first use you will be directed to the Cloudflare login page to authorize the domain in `HOST_DOMAIN`.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `TEXMF_ROOT` | `build/texlive-full/texmf-dist` | Path to `texmf-dist` tree; relative paths are supported for bare-metal only, Docker requires an absolute path |
| `PORT` | `8070` | Port to listen on |
| `REDIS_URL` | — | Redis URL for path caching; disabled if unset |
| `API_ORIGINS` | — | CORS origins: `*`, comma-separated list, or unset for same-origin only |
| `HOST_DOMAIN` | — | Public domain for Cloudflare Tunnel |
| `CLOUDFLARE_API_KEY` | — | Cloudflare Global API token |

## Connecting busytex

Point `TEXLIVE_REMOTE_ENDPOINT` at this server. In `busytex_pipeline.js` the env var is already wired; set it before compiling:

- Local: `http://localhost:8070`
- Production: `https://texlive2026.texlyre.org`