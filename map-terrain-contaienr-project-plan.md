# Self-Hosted Map / Terrain / 3D Buildings Stack — Project Plan

**Project name:** `gev-map-terrain-stack` (separate repo, portable to another machine)
**Goal:** Three containerized services that fully replace Google's photorealistic-globe key with 100% open data, served entirely from local disk after a one-time (then monthly) data pull. No external network calls at request time.
**Audience:** written so a junior engineer can execute it top to bottom without prior geospatial background.

---

## 0. What we're building

| Service | Replaces | Wire contract | Container name |
|---|---|---|---|
| **imagery** | Google Maps tiles / OSM.org | XYZ raster tiles `{z}/{x}/{y}.png` | `gev-imagery` |
| **terrain** | Google 3D Tiles elevation / Cesium World Terrain | `quantized-mesh-1.0` + `layer.json` | `gev-terrain` |
| **buildings** | Google Photorealistic 3D Tiles (extruded, not photoreal) | OGC 3D Tiles `tileset.json` + `.b3dm` | `gev-buildings` |

These are **open, documented wire formats** — not Google- or Cesium-proprietary — so any server that emits them correctly is a drop-in replacement. The God's Eye View app already speaks all three contracts today (against hosted defaults); this project builds local, containerized servers for them and points the app's env vars at your own machine instead.

### Non-negotiable design principles (hold the project to these — they're also what we test for)

1. **Local-first at request time.** Once data is pulled, containers must serve tiles with zero outbound network calls. This is a testable property (see "offline test" in every phase), not just an intention.
2. **Pull once, refresh monthly.** A scheduled job re-pulls source data and rebuilds each service on a monthly cadence. Terrain barely changes between months; imagery and especially buildings (Overture ships true monthly releases) benefit more — monthly is one cadence for all three, kept uniform for simplicity per this plan.
3. **Everything containerized, data on a mounted volume.** No service bakes data into its image layer. Rebuilding the image must never require re-downloading data, and re-downloading data must never require rebuilding the image.
4. **Test before you trust a spec.** Every third-party tool's exact CLI flags / JSON schema / URL layout gets *verified against its running `--help`, `/docs`, or README* before you write a test against it — see the rule below.
5. **Storage is measured, not guessed.** Every phase has a "measure before you commit to downloading" step that produces a real number from a manifest or `HEAD` request, before the bulk download runs.

### The "Verify-before-test" rule

This plan cites real, currently-existing tools and gives you my best-known configuration for each — but exact CLI flags, JSON key names, and URL paths on other people's projects can drift after this plan is written. Wherever a step is marked **⚠ VERIFY**, stop and confirm the real behavior (via `--help`, the tool's `/docs` endpoint, or its README) before writing the test for it. Write the test against **observed reality**, not against this document. This is standard TDD hygiene applied to third-party integrations, not a hedge — treat every ⚠ VERIFY as a mandatory step, not optional reading.

---

## 1. Prerequisites

Install on the build machine (the one that will run this project, which may or may not be the machine ultimately running the God's Eye View app):

```bash
# macOS (Homebrew) — adjust for Linux package manager if the build machine differs
brew install docker docker-compose gdal osmium-tool duckdb jq awscli
```

- **Docker + Docker Compose v2** — runtime for all three services
- **GDAL CLI tools** (`gdalinfo`, `gdalbuildvrt`, `gdal_translate`, `gdalwarp`) — DEM/bathymetry merging
- **osmium-tool** — bounding-box extraction from OpenStreetMap `.pbf` files
- **duckdb** (CLI or Python package) — querying Overture Maps Parquet data
- **jq** — inspecting JSON responses in tests
- **awscli** — pulling from AWS Open Data S3 buckets (`--no-sign-request`, no AWS account needed for public Open Data buckets)

Confirm each is on `PATH` before continuing:

```bash
docker --version && docker compose version && gdalinfo --version \
  && osmium --version && duckdb --version && jq --version && aws --version
```

---

## 2. Repo layout

```
gev-map-terrain-stack/
├── docker-compose.yml
├── .env                          # scope + paths, see §3
├── .env.example
├── README.md
├── scheduler/
│   └── Dockerfile                # tiny cron/ofelia container, runs monthly refresh jobs
├── imagery/
│   ├── scripts/
│   │   ├── fetch-extract.sh
│   │   ├── measure-storage.sh
│   │   └── refresh-monthly.sh
│   └── tests/
│       └── test_imagery_api.sh
├── terrain/
│   ├── datasets.json             # ctod dataset config (see Phase B)
│   ├── scripts/
│   │   ├── list-dem-tiles.sh
│   │   ├── fetch-dem.sh
│   │   ├── fetch-bathymetry.sh
│   │   ├── build-mosaic.sh
│   │   ├── measure-storage.sh
│   │   └── refresh-monthly.sh
│   └── tests/
│       └── test_terrain_api.sh
├── buildings/
│   ├── scripts/
│   │   ├── fetch-overture-buildings.sh
│   │   ├── extrude-to-3dtiles.py
│   │   ├── measure-storage.sh
│   │   └── refresh-monthly.sh
│   └── tests/
│       └── test_buildings_api.sh
├── data/                         # gitignored — the actual mounted volumes live here
│   ├── imagery/                  #   -> osm postgres + rendered tile cache
│   ├── terrain/                  #   -> DEM COGs, mosaic, ctod tile cache
│   └── buildings/                #   -> overture extract, generated 3D Tiles
└── tests/
    └── test_integration.sh       # brings the stack up, hits all three, offline test
```

Add `data/` to `.gitignore` immediately — this repo tracks pipelines and config, never the pulled datasets themselves (they're multi-GB and regenerable).

---

## 3. Milestone 0 — Freeze the scope

Before pulling anything, decide **how much of the world** this stack covers. Don't skip this — it's the single biggest lever on storage and build time, and picking wrong burns hours re-downloading.

Define three tiers in `.env`:

```bash
# .env
SCOPE_TIER=dev            # dev | regional | global — start with dev, prove the pipeline, then widen

# dev tier: a single small bounding box for fast iteration and writing tests against
DEV_BBOX_MINLON=-97.85
DEV_BBOX_MINLAT=30.10
DEV_BBOX_MAXLON=-97.55
DEV_BBOX_MAXLAT=30.45
DEV_BBOX_NAME=austin-tx

# regional tier: one country/continent extract, set once you're ready to scale
REGIONAL_EXTRACT_URL=https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf
REGIONAL_NAME=texas

# global tier: no bbox filtering — full planet. Only flip this on once dev+regional
# have both passed every test in this plan.
```

**Why start with `dev`:** a ~30km bounding box (example above is Austin, TX, since that's already a supported CCTV source region in the God's Eye View app) gives you a full working pipeline in minutes instead of hours, so you can write and pass every test in this plan cheaply before committing to a multi-hour/multi-GB regional or global pull.

### Test — Milestone 0

```bash
# tests/test_scope_frozen.sh
source .env
test -n "$SCOPE_TIER" || { echo "FAIL: SCOPE_TIER not set"; exit 1; }
echo "PASS: scope tier = $SCOPE_TIER"
```

**Acceptance:** `.env` exists, is gitignored for anything with secrets (none expected here, but keep the habit), and `SCOPE_TIER=dev` is the starting value.

---

## 4. Phase A — Imagery tile server (self-hosted OpenStreetMap)

Replaces: `OSM_TILE_BASE_URL` (already a supported env var in the God's Eye View app — this phase requires **zero client-side code changes**, only pointing that env var at your container).

### A0. Get the data

```bash
# imagery/scripts/fetch-extract.sh
mkdir -p data/imagery/pbf

if [ "$SCOPE_TIER" = "dev" ]; then
  # Pull the smallest parent extract that contains the dev bbox, then clip it.
  # ⚠ VERIFY: pick the actual smallest Geofabrik extract covering DEV_BBOX before
  # scripting this for real — for the Austin example that's the "texas" extract.
  curl -L -o data/imagery/pbf/parent.osm.pbf \
    "https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf"
  osmium extract -b "${DEV_BBOX_MINLON},${DEV_BBOX_MINLAT},${DEV_BBOX_MAXLON},${DEV_BBOX_MAXLAT}" \
    data/imagery/pbf/parent.osm.pbf -o "data/imagery/pbf/${DEV_BBOX_NAME}.osm.pbf" --overwrite
elif [ "$SCOPE_TIER" = "regional" ]; then
  curl -L -o "data/imagery/pbf/${REGIONAL_NAME}.osm.pbf" "$REGIONAL_EXTRACT_URL"
else
  curl -L -o data/imagery/pbf/planet.osm.pbf "https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf"
fi
```

### A1. Measure storage before importing

```bash
# imagery/scripts/measure-storage.sh
du -sh data/imagery/pbf/*.osm.pbf
```

**Known reference points** (confirmed 2026-08): planet.pbf ≈ 150 GB compressed, full-planet import DB ≈ 256 GB (512 GB SSD + 64–128 GB RAM recommended for `global` tier). A country extract like Texas is a few GB and imports to tens of GB. A `dev`-tier city bbox extract is typically under 50 MB and imports in well under a minute.

**Test:**
```bash
test "$(du -sm data/imagery/pbf/*.osm.pbf | awk '{print $1}')" -gt 0 || { echo FAIL; exit 1; }
```

### A2. Import and containerize

Use the standard, actively-maintained self-hosted OSM stack image, [`overv/openstreetmap-tile-server`](https://github.com/Overv/openstreetmap-tile-server). ⚠ VERIFY the current image tag and its exact serving URL path against its README right before this step — image interfaces do evolve.

```yaml
# docker-compose.yml (imagery service)
services:
  gev-imagery:
    image: overv/openstreetmap-tile-server:latest
    container_name: gev-imagery
    environment:
      - THREADS=4
    volumes:
      - ./data/imagery/pbf/${DEV_BBOX_NAME}.osm.pbf:/data/region.osm.pbf:ro
      - ./data/imagery/db:/data/database   # postgres data — survives rebuilds
      - ./data/imagery/tiles:/data/tiles   # rendered tile cache
    ports:
      - "8080:80"
```

Import (one-time per data refresh):
```bash
docker compose run --rm gev-imagery import
docker compose up -d gev-imagery
```

### A3. API contract tests (write these BEFORE you trust the container works)

```bash
# imagery/tests/test_imagery_api.sh
set -e
BASE="http://localhost:8080"

# ⚠ VERIFY the exact tile path against the image's README — commonly /tile/{z}/{x}/{y}.png
Z=12; X=$(( (1<<Z) * ( (DEV_BBOX_MINLON+180) / 360 ) | 0 ))  # illustrative — compute real x/y for your bbox
Y=1655  # placeholder — derive with a lon/lat-to-tile calculator for your dev bbox center

status=$(curl -s -o /tmp/tile.png -w "%{http_code}" "$BASE/tile/$Z/$X/$Y.png")
test "$status" = "200" || { echo "FAIL: tile HTTP $status"; exit 1; }

# A valid PNG starts with the 8-byte PNG magic number
magic=$(head -c 8 /tmp/tile.png | xxd -p)
test "$magic" = "89504e470d0a1a0a" || { echo "FAIL: not a valid PNG"; exit 1; }

echo "PASS: imagery tile served and is a valid PNG"
```

**Offline test (proves "completely local"):**
```bash
docker network disconnect bridge gev-imagery 2>/dev/null || true
curl -s -o /dev/null -w "%{http_code}" "$BASE/tile/$Z/$X/$Y.png" | grep -q 200 \
  && echo "PASS: served with no network egress" || echo "FAIL: container needs network at request time"
docker network connect bridge gev-imagery
```

### A4. Monthly refresh

```bash
# imagery/scripts/refresh-monthly.sh
./imagery/scripts/fetch-extract.sh
docker compose run --rm gev-imagery import   # re-import from the fresh extract
docker compose restart gev-imagery
```

### A5. Acceptance criteria for Phase A

- [ ] `docker compose up -d gev-imagery` serves valid PNG tiles over the dev bbox
- [ ] Offline test passes (no egress required at request time)
- [ ] `refresh-monthly.sh` runs end-to-end without manual steps
- [ ] Storage measured and recorded for the chosen tier

---

## 5. Phase B — Terrain server (quantized-mesh, self-hosted)

Replaces: `REARTHTERRAIN_BASE_URL` (already supported — again, zero client code changes needed).

We use [**CTOD**](https://github.com/sogelink-research/ctod) (Cesium Terrain On Demand) rather than pre-baking a global tile pyramid. CTOD generates `quantized-mesh-1.0` tiles on request from local Cloud-Optimized GeoTIFFs (COGs) and caches what's actually requested — this avoids ever needing to pre-tile a whole planet, which is the single biggest storage/time trap in self-hosted terrain.

Docker image (confirmed): `ghcr.io/sogelink-research/ctod:latest`.

### B0. Source data

Two open datasets, merged into one elevation surface — this mirrors exactly what Cesium World Terrain does internally:

- **Land elevation**: [Copernicus DEM GLO-30](https://registry.opendata.aws/copernicus-dem/) — free, ~30 m global (small gaps in a few countries), Cloud-Optimized GeoTIFFs, no signup, hosted at `s3://copernicus-dem-30m/`, tiled in 1°×1° cells.
- **Ocean bathymetry**: [GEBCO_2026 Grid](https://www.gebco.net/data-products-gridded-bathymetry-data/gebco2026-grid) — free, global, single ~7 GB file (netCDF or 8 GeoTIFF tiles), 15 arc-second resolution.

```bash
# terrain/scripts/list-dem-tiles.sh
# Computes the 1°x1° Copernicus DEM tile names covering the dev bbox.
# ⚠ VERIFY the exact tile naming convention against the bucket before trusting
# this pattern — list a couple of known tiles first:
aws s3 ls s3://copernicus-dem-30m/ --no-sign-request | head -20

# Pattern as of 2026 is Copernicus_DSM_COG_10_<N|S><lat>_00_<E|W><lon>_00_DEM —
# confirm this exact string against the `aws s3 ls` output above before scripting
# the download loop for real.
```

```bash
# terrain/scripts/fetch-dem.sh (skeleton — fill in tile names from list-dem-tiles.sh)
mkdir -p data/terrain/dem
while read -r tile; do
  aws s3 cp --no-sign-request "s3://copernicus-dem-30m/${tile}/${tile}.tif" \
    "data/terrain/dem/${tile}.tif"
done < data/terrain/dem_tiles.txt
```

```bash
# terrain/scripts/fetch-bathymetry.sh
mkdir -p data/terrain/bathymetry
curl -L -o data/terrain/bathymetry/gebco_2026.tif \
  "https://www.bodc.ac.uk/data/open_download/gebco/gebco_2026/geotiff/"
  # ⚠ VERIFY current download URL/format on gebco.net — the download portal changes;
  # confirm you're getting a GeoTIFF, not netCDF, or add a gdal_translate conversion step.
```

### B1. Measure storage before committing

```bash
# terrain/scripts/measure-storage.sh
echo "DEM tiles for this bbox:"
du -ch data/terrain/dem/*.tif | tail -1
echo "Bathymetry:"
du -sh data/terrain/bathymetry/
```

**Sizing method for any scope** (don't trust a global number — compute your own): Copernicus DEM tiles are 1°×1° cells, roughly 25–150 MB each depending on terrain complexity. Count = `ceil(lat span) × ceil(lon span)` for your chosen bbox/region. For the `dev` Austin bbox that's a single tile (well under 200 MB). GEBCO is a flat 7 GB regardless of scope (it's one global file you crop from, not per-tile).

### B2. Merge land + ocean into one raster

```bash
# terrain/scripts/build-mosaic.sh
# GEBCO first (base layer, full global coverage incl. ocean), Copernicus DEM tiles
# layered on top (higher-res land data; nodata over ocean lets GEBCO show through).
gdalbuildvrt -srcnodata 0 data/terrain/mosaic.vrt \
  data/terrain/bathymetry/gebco_2026.tif \
  data/terrain/dem/*.tif

# ⚠ VERIFY: confirm ctod can read a .vrt directly via its `cog` parameter/dataset
# config. If it strictly requires a true Cloud-Optimized GeoTIFF, convert:
gdal_translate -of COG -co COMPRESS=DEFLATE data/terrain/mosaic.vrt data/terrain/mosaic.cog.tif
```

### B3. Containerize CTOD

```yaml
# docker-compose.yml (terrain service)
services:
  gev-terrain:
    image: ghcr.io/sogelink-research/ctod:latest
    container_name: gev-terrain
    environment:
      - CTOD_PORT=5000
      - CTOD_TILE_CACHE_PATH=/cache
      - CTOD_DATASET_CONFIG_PATH=/config/datasets.json
      - CTOD_LOGGING_LEVEL=info
      - CTOD_NO_DYNAMIC=true   # only serve the named dataset below, not arbitrary ?cog= URLs
    volumes:
      - ./terrain/datasets.json:/config/datasets.json:ro
      - ./data/terrain/mosaic.cog.tif:/data/mosaic.cog.tif:ro
      - ./data/terrain/cache:/cache
    ports:
      - "5001:5000"
```

```json
// terrain/datasets.json
// ⚠ VERIFY exact key names against `curl http://localhost:5001/docs` once the
// container is running — this is CTOD's own OpenAPI schema, the ground truth.
{
  "gev-terrain": {
    "cog": "/data/mosaic.cog.tif",
    "minZoom": 0,
    "maxZoom": 15
  }
}
```

This gives you a stable endpoint shape matching the app's existing pattern:
`http://localhost:5001/tiles/gev-terrain/layer.json` and `.../{z}/{x}/{y}.terrain`.

### B4. API contract tests

```bash
# terrain/tests/test_terrain_api.sh
set -e
BASE="http://localhost:5001"

status=$(curl -s -o /tmp/layer.json -w "%{http_code}" "$BASE/tiles/gev-terrain/layer.json")
test "$status" = "200" || { echo "FAIL: layer.json HTTP $status"; exit 1; }
jq -e '.tiles and .format' /tmp/layer.json >/dev/null || { echo "FAIL: layer.json missing expected keys"; exit 1; }

status=$(curl -s -o /tmp/tile.terrain -w "%{http_code}" "$BASE/tiles/gev-terrain/2/2/1.terrain")
test "$status" = "200" || { echo "FAIL: terrain tile HTTP $status"; exit 1; }

# quantized-mesh tiles start with a little-endian double (center X) — not a fixed
# magic string like PNG, so the real check is: non-trivial size + gzip-decodable
# if Content-Encoding: gzip was returned.
size=$(stat -f%z /tmp/tile.terrain 2>/dev/null || stat -c%s /tmp/tile.terrain)
test "$size" -gt 100 || { echo "FAIL: terrain tile suspiciously small"; exit 1; }

echo "PASS: terrain layer.json and tile both served correctly"
```

**Offline test:** identical pattern to Phase A — disconnect the container's network, confirm tiles still serve from the local COG + cache.

### B5. Monthly refresh

```bash
# terrain/scripts/refresh-monthly.sh
./terrain/scripts/fetch-dem.sh
./terrain/scripts/fetch-bathymetry.sh
./terrain/scripts/build-mosaic.sh
docker compose restart gev-terrain
```

Note: elevation data genuinely doesn't change monthly in any way that matters visually — this refresh mostly exists to pick up dataset corrections/releases upstream. It's safe to relax this to quarterly later without losing anything meaningful; monthly is kept here only for consistency with the other two services per this plan's scope.

### B6. Acceptance criteria for Phase B

- [ ] `layer.json` and at least one `.terrain` tile served correctly for the dev bbox
- [ ] Offline test passes
- [ ] Mosaic build script is idempotent (re-running it after a fresh DEM pull produces a valid new COG)
- [ ] Storage measured and recorded

---

## 6. Phase C — 3D Buildings server (Overture Maps → OGC 3D Tiles)

This is the layer that gets you *closest* to what Google's photoreal tiles buy visually (real building massing, not just a flat map) — using 100% open data. There's no existing env var for this in the God's Eye View app yet; wiring the client to consume it is a small follow-up code change in that repo, **out of scope for this plan**, which only needs to produce a correct, standards-compliant 3D Tiles endpoint.

### C0. Get the data

Overture Maps ships true **monthly releases** (confirmed cadence, matches this plan's refresh interval exactly) as cloud-native GeoParquet on S3/Azure. Query directly with DuckDB — no need to download the full 176 GB global buildings theme, since DuckDB can filter by bbox over HTTP range requests.

```bash
# buildings/scripts/fetch-overture-buildings.sh
# ⚠ VERIFY the current release string and S3 path at docs.overturemaps.org/getting-data/duckdb
# before running — Overture's release path is a versioned date that changes monthly by design.
RELEASE="2026-XX-XX.0"   # fill in current release

duckdb -c "
INSTALL spatial; INSTALL httpfs;
LOAD spatial; LOAD httpfs;
SET s3_region='us-west-2';
COPY (
  SELECT id, height, num_floors, geometry
  FROM read_parquet('s3://overturemaps-us-west-2/release/${RELEASE}/theme=buildings/type=building/*', filename=true, hive_partitioning=1)
  WHERE bbox.xmin > ${DEV_BBOX_MINLON} AND bbox.xmax < ${DEV_BBOX_MAXLON}
    AND bbox.ymin > ${DEV_BBOX_MINLAT} AND bbox.ymax < ${DEV_BBOX_MAXLAT}
) TO 'data/buildings/overture_buildings.geojson' WITH (FORMAT GDAL, DRIVER 'GeoJSON');
"
```

### C1. Measure storage

```bash
# buildings/scripts/measure-storage.sh
du -sh data/buildings/overture_buildings.geojson
```

For the `dev` bbox this should be a few MB (thousands, not millions, of buildings). For a full country, expect low-to-mid GB of GeoJSON before extrusion — filter by bbox rather than downloading the full 176 GB global theme unless you actually reach the `global` tier.

### C2. Extrude footprints into 3D Tiles

Use [`py3dtilers`](https://github.com/Oslandia/py3dtilers) (Oslandia) — takes GeoJSON polygons + a height attribute, produces a valid `tileset.json` + `.b3dm` set.

```bash
# buildings/scripts/extrude-to-3dtiles.py (conceptual — ⚠ VERIFY exact CLI flags via
# `py3dtilers --help` right before running, this tool's interface may have changed)
py3dtilers Buildings \
  --obj data/buildings/overture_buildings.geojson \
  --height_property height \
  --geometric_error 50 \
  --out data/buildings/tileset
```

**Height fallback heuristic** (document this decision in the script): Overture buildings carry `height` when known; where it's null, fall back to `num_floors * 3` meters; where both are null, use a flat default (e.g., 6 m, roughly two stories) rather than dropping the building. Record this choice in a code comment — it's a real trade-off a future reader needs to know about, not a hidden default.

### C3. Serve as static files

No daemon logic needed — a 3D Tiles tileset is just static files (`tileset.json` + binary `.b3dm` content) with CORS enabled.

```yaml
# docker-compose.yml (buildings service)
services:
  gev-buildings:
    image: nginx:alpine
    container_name: gev-buildings
    volumes:
      - ./data/buildings/tileset:/usr/share/nginx/html:ro
      - ./buildings/nginx-cors.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "5002:80"
```

```nginx
# buildings/nginx-cors.conf
server {
    listen 80;
    root /usr/share/nginx/html;
    add_header Access-Control-Allow-Origin *;
    location / { try_files $uri $uri/ =404; }
}
```

### C4. API contract tests

```bash
# buildings/tests/test_buildings_api.sh
set -e
BASE="http://localhost:5002"

status=$(curl -s -o /tmp/tileset.json -w "%{http_code}" "$BASE/tileset.json")
test "$status" = "200" || { echo "FAIL: tileset.json HTTP $status"; exit 1; }

# OGC 3D Tiles spec requires these top-level keys — this part of the check IS
# a stable external standard, not a guess.
jq -e '.asset.version and .geometricError and .root' /tmp/tileset.json >/dev/null \
  || { echo "FAIL: tileset.json is not spec-compliant"; exit 1; }

# Spot-check the first content URI referenced actually resolves and is a valid B3DM
uri=$(jq -r '.root.content.uri // .root.children[0].content.uri' /tmp/tileset.json)
status=$(curl -s -o /tmp/first.b3dm -w "%{http_code}" "$BASE/$uri")
test "$status" = "200" || { echo "FAIL: b3dm content HTTP $status"; exit 1; }
magic=$(head -c 4 /tmp/first.b3dm)
test "$magic" = "b3dm" || { echo "FAIL: content is not a valid B3DM (magic=$magic)"; exit 1; }

echo "PASS: tileset.json and first B3DM tile both valid"
```

**Offline test:** same pattern — this one trivially passes since nginx serves static files with no external calls ever, but run it anyway to keep the test suite uniform across all three services.

### C5. Monthly refresh

```bash
# buildings/scripts/refresh-monthly.sh
./buildings/scripts/fetch-overture-buildings.sh   # pulls the new monthly Overture release
./buildings/scripts/extrude-to-3dtiles.py
docker compose restart gev-buildings
```

### C6. Acceptance criteria for Phase C

- [ ] `tileset.json` is OGC 3D Tiles spec-compliant and its referenced content resolves
- [ ] Offline test passes
- [ ] Height fallback heuristic documented in the extrusion script
- [ ] Storage measured and recorded

---

## 7. Phase D — Orchestration & scheduled refresh

### D0. Bring the whole stack up together

```yaml
# docker-compose.yml (top-level, combining all services above)
services:
  gev-imagery:
    # ... as defined in Phase A
  gev-terrain:
    # ... as defined in Phase B
  gev-buildings:
    # ... as defined in Phase C
  gev-scheduler:
    build: ./scheduler
    volumes:
      - ./:/stack:ro
      - /var/run/docker.sock:/var/run/docker.sock
```

### D1. Monthly scheduler

Simplest reliable option: a tiny container running `cron` (or [`ofelia`](https://github.com/mcuadros/ofelia) if you want compose-label-driven scheduling instead of a crontab file) that calls each phase's `refresh-monthly.sh` on the 1st of the month.

```dockerfile
# scheduler/Dockerfile
FROM alpine:latest
RUN apk add --no-cache docker-cli bash curl gdal duckdb aws-cli
COPY crontab /etc/crontabs/root
CMD ["crond", "-f"]
```

```
# scheduler/crontab
0 3 1 * * /stack/imagery/scripts/refresh-monthly.sh   >> /var/log/refresh-imagery.log 2>&1
15 3 1 * * /stack/terrain/scripts/refresh-monthly.sh  >> /var/log/refresh-terrain.log 2>&1
30 3 1 * * /stack/buildings/scripts/refresh-monthly.sh >> /var/log/refresh-buildings.log 2>&1
```

### D2. Integration test — the whole stack, offline

```bash
# tests/test_integration.sh
docker compose up -d
sleep 10

./imagery/tests/test_imagery_api.sh
./terrain/tests/test_terrain_api.sh
./buildings/tests/test_buildings_api.sh

echo "--- Full offline test: disconnect all three, confirm all still serve ---"
for svc in gev-imagery gev-terrain gev-buildings; do
  docker network disconnect bridge "$svc" 2>/dev/null || true
done
./imagery/tests/test_imagery_api.sh
./terrain/tests/test_terrain_api.sh
./buildings/tests/test_buildings_api.sh
for svc in gev-imagery gev-terrain gev-buildings; do
  docker network connect bridge "$svc"
done

echo "ALL PASS"
```

**This is the acceptance gate for the whole project.** Nothing moves to `regional` or `global` scope until this passes clean on `dev` scope.

---

## 8. Phase E — Pointing the God's Eye View app at your stack

This is configuration only, in the **other** repo (`gods-eye-view`), not this one. No client code changes needed for imagery or terrain — both env vars already exist:

```bash
# gods-eye-view/.env
OSM_TILE_BASE_URL=http://localhost:8080/tile        # ⚠ VERIFY exact path from Phase A3
REARTHTERRAIN_BASE_URL=http://localhost:5001/tiles/gev-terrain
```

For imagery to actually become the *default* globe (not just the OSM fallback stack), the earlier finding still applies: `src/main.js` currently throws if `GOOGLE_MAPS_API_KEY` is unset. Relaxing that hard requirement so the app boots into the `osm` stack by default is a separate, small change in the `gods-eye-view` repo — not part of this plan, flagged here only so it isn't forgotten when you get to integration.

The **buildings** layer has no existing hook in `mapStackController.js` — wiring it in (loading `http://localhost:5002/tileset.json` as a `Cesium3DTileset` layered over the terrain, similar to how `googleTileset` is loaded today) is future work in the other repo, once this stack proves itself.

**Manual smoke test:** with all three containers up, open the God's Eye View app pointed at the two wired env vars above and confirm the globe renders with real imagery and real terrain relief over the dev bbox, with no requests to `googleapis.com` or `reearth.land` in the browser Network tab.

---

## 9. Storage budget summary

| Tier | Imagery (OSM) | Terrain (DEM+bathy) | Buildings (Overture, filtered) | Total (rough) |
|---|---|---|---|---|
| **dev** (single small bbox) | < 50 MB pbf, < 500 MB imported | < 200 MB (1–4 DEM tiles) + 7 GB shared GEBCO | few MB GeoJSON, few MB tileset | **~10 GB** (dominated by the one-time shared 7 GB GEBCO grid) |
| **regional** (one country/state) | few GB pbf → tens of GB imported | tens of tiles × ~50–150 MB + shared GEBCO | low GB GeoJSON → similar extruded | **tens of GB** |
| **global** | 150 GB pbf → ~256 GB imported (512 GB SSD + 64–128 GB RAM recommended) | measure via `list-dem-tiles.sh` manifest sum before committing — do not assume a number | 176 GB source parquet (query via DuckDB range requests, don't bulk-download) → filtered/extruded output much smaller | **low TB**, imagery-import dominant |

The `global` terrain number is intentionally left as "measure it" rather than a fixed figure — Copernicus DEM's total dataset size wasn't independently confirmable at the time this plan was written; Milestone B1's manifest-summing step gives you a real, current number for whatever bbox you actually choose, which is more trustworthy than any number in this document.

---

## 10. Portability — exporting to another machine

1. Commit everything in the repo tree **except** `data/` (already gitignored) — the whole point of `refresh-monthly.sh` scripts is that data is regenerable, not that it needs to travel with the code.
2. On the new machine: clone the repo, run prerequisites (§1), copy `.env`, then run each phase's fetch/build scripts fresh (§4–6) rather than trying to move `data/` — it's faster and guarantees you land on the current monthly release rather than a stale copy.
3. Exception: if bandwidth on the new machine is constrained, `rsync -avP data/ newmachine:/path/to/gev-map-terrain-stack/data/` is fine — nothing in the pipeline requires a fresh pull, it's just the simpler default.
4. Re-run `tests/test_integration.sh` on the new machine before considering the migration done — this is the real acceptance gate for "it works on the new machine," not just "the files copied."

---

## 11. Troubleshooting runbook

| Symptom | Likely cause | Fix |
|---|---|---|
| `openstreetmap-tile-server import` hangs or OOMs | Not enough RAM for the chosen tier | Drop to a smaller extract, or add swap/RAM per switch2osm guidance (planet needs 64–128 GB) |
| CTOD returns `500` on `.terrain` requests | Mosaic COG has no valid data at that tile's location, or isn't actually COG-profiled | Check `gdalinfo data/terrain/mosaic.cog.tif` for `LAYOUT=COG`; re-run `gdal_translate -of COG` |
| `tileset.json` content URI 404s | Relative path mismatch between `py3dtilers` output and nginx root | Confirm `root` in nginx config matches the actual `--out` directory structure |
| DuckDB Overture query returns 0 rows | Release string stale, or bbox filter uses swapped lon/lat | Re-check current release at docs.overturemaps.org; confirm `bbox.xmin/xmax` = longitude, `bbox.ymin/ymax` = latitude |
| Offline test fails (container needs network) | A service is silently falling back to a remote URL (e.g., ctod's dynamic mode still pointed at a `vsicurl` remote COG) | Set `CTOD_NO_DYNAMIC=true` and confirm `datasets.json` points at a local path, not a URL |

---

## 12. Definition of done

- [ ] All of §4–6's per-phase acceptance criteria checked
- [ ] `tests/test_integration.sh` passes clean, including the full offline test
- [ ] Monthly scheduler container running and its three cron entries verified with a manual trigger (don't wait a month to find out cron is misconfigured)
- [ ] Storage actually measured (not estimated) and recorded in this file's §9 table for whichever tier you actually ran
- [ ] God's Eye View app's `.env` updated and manually verified to render the dev bbox using only local containers (Network tab shows no Google/Cesium/Overture/OSM.org requests at runtime)
