# 01 — Architecture

## 1. System overview

```
                                    ┌──────────────────────────────┐
                                    │  Authoring (humans + scripts) │
                                    │  data/seed/*.json + *.geojson │
                                    └───────────────┬──────────────┘
                                                    │  goose migrate + seed loader (Go)
                                                    ▼
┌─────────────────┐   HTTP/JSON    ┌──────────────────────────────┐
│  Next.js 16     │ ─────────────► │  Go API (chi)                │
│  (App Router)   │ ◄───────────── │  /api/v1/...                 │
│  MapLibre GL    │   GeoJSON      │  - aggregate "state" endpoint │
└─────────────────┘                │  - resource endpoints         │
        │                          │  - search                     │
        │ static map style/tiles   └───────────────┬──────────────┘
        ▼                                           │ sqlc (typed)
┌─────────────────┐                                 ▼
│ Map tiles (CDN  │                  ┌──────────────────────────────┐
│ or self-host)   │                  │ PostgreSQL 16 + PostGIS 3.4   │
└─────────────────┘                  └──────────────────────────────┘
```

### Why this shape

- **The map basemap and the historical data are separate concerns.** MapLibre renders a
  basemap (coastlines, sea, optional modern context) from a vector/raster tile source. Our
  *historical* layers (territories, cities, events) are GeoJSON we serve ourselves and add
  as MapLibre sources on top. Keep them decoupled so swapping the basemap never touches
  history data.
- **Postgres + PostGIS, not flat files at runtime.** Seed data is authored as files (easy to
  diff, review, version), but served from Postgres so "state at year Y" is one indexed query
  rather than loading and filtering megabytes of GeoJSON in the client. See
  [02-data-models.md](./02-data-models.md) §7 for the file→DB pipeline.
- **One aggregate endpoint + granular endpoints.** The slider needs a single round-trip per
  year (`GET /state?year=`). Detail panels and search use granular endpoints. See
  [03-api.md](./03-api.md).

## 2. The core abstraction: `year → state`

Define a pure projection. Given an integer `year ∈ [1000, 1500]`, the API returns a
`WorldState`:

```
WorldState(year) = {
  year,
  territories:  FeatureCollection<Polygon>   // political control valid AT year
  cities:       FeatureCollection<Point>      // settlements + size valid AT year
  events:       FeatureCollection<Point>      // events occurring IN year (± window)
  monarchs:     Monarch[]                      // rulers reigning AT year (per polity)
}
```

Everything downstream is a deterministic function of this. This determinism is what makes
the timeline, play/pause animation, deep-linking (`?year=1066`), and caching all trivial.

### Year granularity vs precise dates

- The **slider and all temporal filtering** operate on integer **years** (snap-friendly,
  cache-friendly, matches the fuzziness of medieval sources).
- **Events** additionally carry a precise/fuzzy date for *display* (`1066-10-14`, or "c. 1349").
  Filtering still happens by year; the precise date is presentational. See data-models §3.4.

## 3. Tech stack & key library choices

### Backend (Go)
| Concern | Choice | Rationale |
|--------|--------|-----------|
| Router | `chi` | Stdlib-compatible `http.Handler`, middleware, no framework lock-in |
| DB driver | `pgx` (v5) | Best Postgres driver, native PostGIS-friendly |
| Queries | `sqlc` | Compile SQL → typed Go; no ORM magic, full control over spatial SQL |
| Migrations | `goose` | Simple, SQL-first, versioned |
| Config | `env` + `.env` (godotenv in dev) | 12-factor |
| Logging | `slog` (stdlib) | Structured, no dep |
| Spatial | PostGIS functions, output as GeoJSON via `ST_AsGeoJSON` | Let the DB build GeoJSON |

### Frontend (Next.js 16)
| Concern | Choice | Rationale |
|--------|--------|-----------|
| Framework | Next.js 16 App Router, React 19 | Server Components for shell, Client Components for map |
| Map | MapLibre GL JS (via thin React wrapper, no react-map-gl unless needed) | Full control of sources/layers; MapLibre is client-only |
| Server cache | TanStack Query | Caches per-year `WorldState`, dedupes, prefetch on hover |
| Client state | Zustand | One tiny store for `currentYear`, play state, selected event |
| Styling | Tailwind CSS | Fast UI; map overlays are absolutely-positioned panels |
| Types | TypeScript, shared types generated from API | Single source of truth (see §5) |

## 4. Repository layout

```
atlas-temporum/
├── docs/                       # this folder
├── backend/
│   ├── cmd/api/main.go         # entrypoint
│   ├── cmd/seed/main.go        # seed loader (files → DB)
│   ├── internal/
│   │   ├── api/                # http handlers, router, middleware
│   │   ├── domain/             # Go structs (the models) + business rules
│   │   ├── store/              # sqlc-generated + query wrappers
│   │   └── geojson/            # GeoJSON encoding helpers
│   ├── db/
│   │   ├── migrations/         # goose .sql files
│   │   └── queries/            # sqlc .sql source
│   ├── sqlc.yaml
│   └── go.mod
├── frontend/
│   ├── app/                    # Next.js 16 App Router
│   ├── components/
│   ├── lib/                    # api client, types, hooks
│   ├── store/                  # zustand
│   └── package.json
├── data/
│   ├── seed/                   # authored source-of-truth JSON/GeoJSON
│   └── examples/               # small fixtures used in docs/tests
└── docker-compose.yml          # postgres+postgis for local dev
```

## 5. Type sharing (one source of truth)

The data shapes are defined once and flow outward. Recommended approach:

1. Define the canonical shapes in the **SQL schema + sqlc** (Go structs are generated).
2. Hand-write the API DTOs in Go (they're a thin presentation layer over domain).
3. Generate **TypeScript types** for the frontend from the API. Two options:
   - **OpenAPI**: annotate handlers / write an `openapi.yaml`, run `openapi-typescript`.
   - **Lightweight**: keep a single `frontend/lib/types.ts` mirrored by hand against the API
     doc. Acceptable for MVP given the small surface.

Pick OpenAPI if you expect the API to grow; hand-mirrored types are fine to start. Either
way, **GeoJSON shapes use the standard `geojson` TS types** (`Feature`, `FeatureCollection`)
and our custom data lives in `feature.properties`.

## 6. Data flow for one slider move

1. User drags slider → Zustand `setYear(1215)` (debounced/throttled to ~animation frame).
2. A `useWorldState(1215)` hook (TanStack Query) returns cached data or fetches
   `GET /api/v1/state?year=1215`.
3. Map effect diffs the new `WorldState` against current MapLibre sources and calls
   `source.setData(...)` for `territories`, `cities`, `events`. No full re-render of the map.
4. Overlay panels (monarch bar, event list) re-render from the same data.
5. Prefetch: while playing, prefetch `year+1` (and key years) so playback is smooth.

## 7. Environments & deployment (brief)

- **Local:** `docker-compose up` (Postgres+PostGIS), `go run ./cmd/api`, `next dev`.
- **Prod (MVP):** API as a container; managed Postgres with PostGIS; Next.js on Vercel or a
  Node container. Put a CDN/`Cache-Control` in front of `/state` (data is immutable per year).
- See [03-api.md](./03-api.md) §6 for caching headers that make the whole app feel instant.
