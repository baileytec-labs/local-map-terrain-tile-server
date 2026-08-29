# gev-map-terrain-stack

A self-hosted map, terrain, and 3D buildings tile server stack that fully replaces Google's photorealistic globe with 100% open data, served entirely from local disk after a one-time (then monthly) data pull.

## What this is

Three containerized services that replace Google Maps / Google Earth's 3D tiles:

| Service | Replaces | Format | Port |
|---|---|---|---|
| **Imagery** (`gev-imagery`) | Google Maps tiles / OSM.org | XYZ raster tiles (`{z}/{x}/{y}.png`) | 8080 |
| **Terrain** (`gev-terrain`) | Cesium World Terrain | `quantized-mesh-1.0` + `layer.json` | 5001 |
| **Buildings** (`gev-buildings`) | Google Photorealistic 3D Tiles | OGC 3D Tiles (`tileset.json` + `.b3dm`) | 5002 |

These are **open, documented wire formats** — not Google- or Cesium-proprietary — so any client that speaks these contracts can use this stack as a drop-in replacement.

## Prerequisites

Install these tools on your machine before running the stack:

```bash
# Windows (Chocolatey)
choco install docker-desktop gdal duckdb jq awscli

# macOS (Homebrew)
brew install docker docker-compose gdal duckdb jq awscli

# Linux (Debian/Ubuntu)
sudo apt install docker.io docker-compose-plugin gdal-bin duckdb jq awscli
```

Confirm each is on your `PATH`:

```bash
docker --version && docker compose version && gdalinfo --version
duckdb --version && jq --version && aws --version
```

Required tools:

- **Docker + Docker Compose v2** — runtime for all three services
- **GDAL CLI tools** (`gdalinfo`, `gdalbuildvrt`, `gdal_translate`) — DEM/bathymetry merging
- **DuckDB** — querying Overture Maps Parquet data
- **jq** — inspecting JSON responses in tests
- **awscli** — pulling from AWS Open Data S3 buckets (`--no-sign-request`, no AWS account needed)

## Quick start

### 1. Configure scope

Copy the example environment file and choose your scope tier:

```bash
cp .env.example .env
```

Edit `.env` and set `SCOPE_TIER`:

- **`dev`** — Single small bounding box (Austin, TX). Fastest to set up. Use this first to prove the pipeline.
- **`regional`** — One country/state extract. Larger storage and build time.
- **`global`** — Full planet. Requires 150+ GB for imagery import, significant storage for terrain and buildings.

### 2. Start the services

```bash
# Build and start all services
docker compose up -d gev-imagery gev-terrain gev-buildings
```

### 3. Import OSM data (imagery)

The imagery service needs a one-time import of OpenStreetMap data:

```bash
docker compose run --rm gev-imagery import
```

This imports the OSM extract into the tile server's internal database. For `dev` scope this takes under a minute. For `global` scope it can take 30+ minutes.

### 4. Download terrain data

```bash
# List the DEM tiles covering your bbox
call terrain\scripts\list-dem-tiles.bat

# Download the tiles (creates data/terrain/dem_tiles.txt if missing)
call terrain\scripts\fetch-dem.bat

# Download bathymetry data
call terrain\scripts\fetch-bathymetry.bat

# Merge into a single elevation surface
call terrain\scripts\build-mosaic.bat
```

### 5. Download and convert buildings data

```bash
# Download Overture Maps building footprints
call buildings\scripts\fetch-overture-buildings.bat

# Extrude footprints into 3D Tiles
call buildings\scripts\extrude-to-3dtiles.bat
```

### 6. Run the integration test

```bash
call tests\test_integration.bat
```

This starts all services, tests each API endpoint, and then disconnects the containers from the network to verify they serve tiles completely offline.

## Monthly refresh

Each service has a `refresh-monthly.bat` script that pulls fresh data and rebuilds the tile cache:

```bash
# Refresh all three services
call imagery\scripts\refresh-monthly.bat
call terrain\scripts\refresh-monthly.bat
call buildings\scripts\refresh-monthly.bat
```

Or run the scheduler container (automated, runs on the 1st of each month):

```bash
docker compose up -d gev-scheduler
```

The scheduler runs at 3:00 AM on the 1st of each month. You can trigger a refresh manually at any time:

```bash
docker exec gev-scheduler /stack/imagery/scripts/refresh-monthly.sh
```

## Architecture

```
gev-map-terrain-stack/
├── docker-compose.yml          # All services defined here
├── .env                        # Scope + paths (gitignored)
├── .env.example                # Template for .env
├── .gitignore
├── README.md
├── scheduler/
│   ├── Dockerfile              # Tiny cron container
│   └── crontab                 # Monthly refresh schedule
├── imagery/
│   ├── scripts/
│   │   ├── fetch-extract.bat   # Download OSM PBF + extract bbox
│   │   ├── measure-storage.bat # Report PBF file sizes
│   │   └── refresh-monthly.bat # Full fetch + import + restart
│   └── tests/
│       └── test_imagery_api.bat # Validate tile HTTP 200 + PNG
├── terrain/
│   ├── datasets.json           # CTOD dataset config
│   ├── scripts/
│   │   ├── list-dem-tiles.bat
│   │   ├── fetch-dem.bat
│   │   ├── fetch-bathymetry.bat
│   │   ├── build-mosaic.bat
│   │   ├── measure-storage.bat
│   │   └── refresh-monthly.bat
│   └── tests/
│       └── test_terrain_api.bat
├── buildings/
│   ├── scripts/
│   │   ├── fetch-overture-buildings.bat
│   │   ├── extrude-to-3dtiles.bat
│   │   ├── measure-storage.bat
│   │   └── refresh-monthly.bat
│   ├── nginx-cors.conf         # CORS headers for 3D Tiles
│   └── tests/
│       └── test_buildings_api.bat
├── data/                       # Gitignored — mounted volumes
│   ├── imagery/
│   ├── terrain/
│   └── buildings/
└── tests/
    └── test_integration.bat    # Full stack + offline test
```

## Data sources

| Service | Source | License | Update frequency |
|---|---|---|---|
| Imagery | OpenStreetMap | Open Database License (ODbL) | Continuous |
| Terrain (land) | Copernicus DEM GLO-30 | Creative Commons BY 4.0 | Quarterly |
| Terrain (ocean) | GEBCO_2026 Grid | Creative Commons BY 4.0 | Annual |
| Buildings | Overture Maps | Creative Commons BY 4.0 | Monthly |

All data is downloaded from public sources — no API keys or accounts required:

- **OSM extracts**: `download.geofabrik.de`
- **Copernicus DEM**: `s3://copernicus-dem-30m/` (AWS Open Data)
- **GEBCO**: `gebco.net`
- **Overture Maps**: `s3://overturemaps-us-west-2/release/` (AWS Open Data)

## Storage estimates

| Tier | Imagery | Terrain | Buildings | Total |
|---|---|---|---|---|
| **dev** (single bbox) | < 50 MB PBF | < 200 MB DEM + 7 GB GEBCO | Few MB | ~10 GB |
| **regional** (one state) | Few GB PBF | Tens of tiles + shared GEBCO | Low GB | Tens of GB |
| **global** | 150 GB PBF | Full planet DEM + GEBCO | Full planet parquet | Low TB |

The terrain storage is dominated by the one-time 7 GB GEBCO bathymetry file. DEM tiles are ~25–150 MB each depending on terrain complexity.

## Testing

### Per-service tests

Each service has a test script that validates its API contract:

```bash
call imagery\tests\test_imagery_api.bat
call terrain\tests\test_terrain_api.bat
call buildings\tests\test_buildings_api.bat
```

### Full integration test

```bash
call tests\test_integration.bat
```

This runs all per-service tests, then disconnects all containers from the network and re-runs them to verify the "local-first at request time" design principle — tiles must serve with zero outbound network calls.

### Scope test

```bash
call tests\test_scope_frozen.bat
```

Validates that `SCOPE_TIER` is set in `.env`.

## Connecting to a client app

If you have a client app that consumes these tile formats, point its configuration at your local stack:

```bash
# Imagery (XYZ tiles)
OSM_TILE_BASE_URL=http://localhost:8080/tile

# Terrain (quantized-mesh)
REARTHTERRAIN_BASE_URL=http://localhost:5001/tiles/gev-terrain

# Buildings (3D Tiles)
BUILDINGS_TILESET_URL=http://localhost:5002/tileset.json
```

## Portability — moving to another machine

1. Commit everything in the repo (except `data/` which is gitignored).
2. On the new machine: clone the repo, install prerequisites, copy `.env`.
3. Run each phase's fetch/build scripts (`fetch-extract.bat`, `fetch-dem.bat`, `fetch-bathymetry.bat`, `fetch-overture-buildings.bat`, `extrude-to-3dtiles.bat`).
4. Run `tests/test_integration.bat` to verify everything works.

If bandwidth is constrained, you can `rsync` the `data/` directory instead of re-downloading:

```bash
rsync -avP data/ newmachine:/path/to/gev-map-terrain-stack/data/
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `import` hangs or OOMs | Not enough RAM for the chosen tier | Drop to a smaller extract, or add swap/RAM |
| CTOD returns 500 on `.terrain` requests | Mosaic COG has no valid data or isn't COG-profiled | Check with `gdalinfo data/terrain/mosaic.cog.tif` for `LAYOUT=COG` |
| `tileset.json` content URI 404s | Relative path mismatch between py3dtilers output and nginx root | Confirm `root` in nginx config matches the actual `--out` directory |
| DuckDB Overture query returns 0 rows | Release string stale, or bbox filter uses swapped lon/lat | Re-check current release at docs.overturemaps.org |
| Offline test fails | Container needs network at request time | Confirm all services point at local data, not remote URLs |

## Design principles

1. **Local-first at request time.** Once data is pulled, containers serve tiles with zero outbound network calls.
2. **Pull once, refresh monthly.** A scheduled job re-pulls source data and rebuilds each service on a monthly cadence.
3. **Everything containerized, data on a mounted volume.** No service bakes data into its image layer.
4. **Test before you trust a spec.** Every third-party tool's exact CLI flags and JSON schema get verified against its running `--help`, `/docs`, or README before writing tests.
5. **Storage is measured, not guessed.** Every phase has a "measure before you commit to downloading" step that produces a real number before bulk download.
