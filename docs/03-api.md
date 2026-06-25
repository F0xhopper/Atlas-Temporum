# 03 — API Design

Go HTTP API (`chi`). Read-only for MVP. All responses JSON; geometry as GeoJSON. Versioned
under `/api/v1`. The design goal: **one fast round-trip per slider year**, plus granular
endpoints for detail panels and search.

## 1. Conventions

- **Base path:** `/api/v1`
- **Format:** `application/json`. Geometry endpoints return GeoJSON `FeatureCollection`s
  (RFC 7946) where our data lives in `feature.properties`.
- **Years:** integer query param `year`, validated to `[1000, 1500]`. Out-of-range → `400`.
- **IDs in URLs:** always **slugs** (`/events/battle-of-hastings`), never numeric PKs.
- **Naming:** JSON fields `camelCase`. Enum values are the lowercase strings from data-models §4.
- **Errors:** consistent envelope (see §5).
- **CORS:** allow the frontend origin; `GET, OPTIONS` only.
- **Time:** everything is deterministic per `year`, which makes aggressive caching safe (§6).

## 2. Endpoint summary

| Method | Path | Purpose |
|-------|------|---------|
| GET | `/api/v1/state?year={y}` | **Aggregate**: everything to draw one frame |
| GET | `/api/v1/territories?year={y}` | Territories FeatureCollection at year |
| GET | `/api/v1/cities?year={y}` | Cities FeatureCollection (size resolved at year) |
| GET | `/api/v1/events?year={y}&window={w}` | Events FeatureCollection in/near year |
| GET | `/api/v1/events/{slug}` | Full event detail (for the panel) |
| GET | `/api/v1/monarchs?year={y}` | Monarch(s) reigning at year |
| GET | `/api/v1/search?q={text}` | Cross-entity search (cities, events, monarchs) |
| GET | `/api/v1/meta` | Static config: bounds, key years, legend, year range |
| GET | `/healthz` | Liveness |

The granular endpoints exist for prefetching, debugging, and the search "jump-to" flow; the
frontend mostly uses `/state` and `/events/{slug}`.

## 3. Endpoint details

### 3.1 `GET /state?year={y}` — the headline endpoint
Returns the full `WorldState` (data-models §6). One request per slider position.

`200` response:
```json
{
  "year": 1066,
  "territories": { "type": "FeatureCollection", "features": [ /* Polygon features */ ] },
  "cities":      { "type": "FeatureCollection", "features": [ /* Point features */ ] },
  "events":      { "type": "FeatureCollection", "features": [ /* Point features */ ] },
  "monarchs": [
    { "personSlug": "harold-godwinson", "name": "Harold II", "title": "King of England",
      "reignFrom": 1066, "reignTo": 1066, "isDisputed": false }
  ]
}
```
See [../data/examples/world_state.json](../data/examples/world_state.json) for a fuller body.

Implementation note: prefer assembling this in **one DB round-trip per layer** (4–5 small
indexed queries) and marshalling in Go, *or* a single SQL function returning a JSON document.
Both are fine; start with separate queries for clarity, optimize later.

### 3.2 `GET /territories?year=` and `/cities?year=`
- **Territories:** features are `MultiPolygon`; `properties` = `TerritoryProps`
  (`politySlug, name, color, kind, confidence`). Query = territory_version valid at year.
- **Cities:** features are `Point`; `properties` = `CityProps` (`slug, name, sizeRank`).
  `sizeRank` is resolved for the year. **Resolution mode** via `?size=step|lerp` (default
  `lerp`): `step` = most-recent sample ≤ year; `lerp` = linear interpolation between the
  bracketing samples → fractional `sizeRank` (e.g. `4.3`) for smooth growth. Cities founded
  after `year` are omitted.

### 3.3 `GET /events?year={y}&window={w}`
Events whose span intersects `[year-w, year+w]`. `window` default `0` (exact year). Use a
small window (e.g. `2`) if you want markers to fade in/out around their year as the slider
moves. Features are `Point` (events with null geometry are excluded from the FeatureCollection
but still searchable). `properties` = `EventProps`. Sort/emit `importance` so the client can
show only high-importance markers when zoomed out.

### 3.4 `GET /events/{slug}` — detail panel
Full `EventDetail`: description, outcome, `participants[]` (key figures with roles), and
location. This is fetched lazily when the user clicks a marker, keeping `/state` lean.
```json
{
  "slug": "battle-of-hastings", "title": "Battle of Hastings", "type": "battle",
  "year": 1066, "dateDisplay": "14 October 1066", "isCirca": false,
  "summary": "Decisive Norman victory over the Anglo-Saxons.",
  "description": "Duke William of Normandy defeated King Harold II ...",
  "outcome": "Norman victory; William crowned King of England on 25 December 1066.",
  "citySlug": "hastings", "importance": 5,
  "participants": [
    { "personSlug": "william-i", "name": "William the Conqueror", "role": "victor" },
    { "personSlug": "harold-godwinson", "name": "Harold II", "role": "defeated" }
  ],
  "location": { "lng": 0.4876, "lat": 50.9116 }
}
```

### 3.5 `GET /monarchs?year=`
- `monarchs`: array (possibly >1 during disputes). Powers the top bar.

### 3.6 `GET /search?q={text}`
Cross-entity search for the search box. Returns a flat ranked list of hits, each with enough
to drive the "jump to location + move timeline + highlight" behavior.
```json
{
  "query": "hastings",
  "results": [
    { "kind": "event", "slug": "battle-of-hastings", "label": "Battle of Hastings",
      "sublabel": "Battle · 1066", "year": 1066, "lng": 0.4876, "lat": 50.9116 },
    { "kind": "city", "slug": "hastings", "label": "Hastings",
      "sublabel": "City", "year": null, "lng": 0.5728, "lat": 50.8543 }
  ]
}
```
`kind ∈ {event, city, monarch}`. MVP search = Postgres `ILIKE`/`pg_trgm` over names/titles
(+ optional `tsvector` full-text). Each result carries `year` (so the slider can snap) and
`lng/lat` (so the map can fly to it). Selecting a result: move timeline to `year`, `flyTo`
location, and (for events) open the detail panel + highlight the marker.

### 3.7 `GET /meta` — static client config
One call on app load. Lets the frontend avoid hardcoding constants.
```json
{
  "yearRange": { "min": 1000, "max": 1500 },
  "keyYears": [1000, 1066, 1215, 1348, 1455, 1485, 1500],
  "bounds": { "west": -11.0, "south": 49.5, "east": 2.2, "north": 61.0 },
  "defaultCenter": { "lng": -2.5, "lat": 54.0 }, "defaultZoom": 5,
  "legend": [
    { "kind": "kingdom", "label": "Kingdom" }, { "kind": "earldom", "label": "Earldom" }
  ],
  "eventTypes": [
    { "type": "battle", "label": "Battle", "icon": "⚔" },
    { "type": "coronation", "label": "Coronation", "icon": "👑" }
  ]
}
```

## 4. Building GeoJSON in the query (recommended pattern)

Let PostGIS build the FeatureCollection so Go just streams it. Example for territories:
```sql
SELECT json_build_object(
  'type', 'FeatureCollection',
  'features', COALESCE(json_agg(json_build_object(
     'type', 'Feature',
     'geometry', ST_AsGeoJSON(tv.geom)::json,
     'properties', json_build_object(
        'politySlug', p.slug, 'name', p.name, 'color',
        COALESCE(tv.color_override, p.color), 'kind', p.kind, 'confidence', tv.confidence)
  )), '[]'::json)
)
FROM territory_version tv JOIN polity p ON p.id = tv.polity_id
WHERE tv.valid_from <= $1 AND (tv.valid_to IS NULL OR tv.valid_to > $1);
```
The handler scans a single `[]byte` and writes it through. Same shape for cities/events. This
keeps Go thin and avoids N+1 marshalling. `sqlc` supports this with a `:one` query returning
`json.RawMessage`.

## 5. Errors

Consistent envelope, correct status codes:
```json
{ "error": { "code": "INVALID_YEAR", "message": "year must be between 1000 and 1500" } }
```
| Status | When |
|-------|------|
| 400 | bad/missing `year`, `q` too short, malformed params |
| 404 | unknown slug (`/events/{slug}`) |
| 422 | semantically invalid (rare for read API) |
| 500 | unexpected; log with `slog`, never leak internals |

Codes are stable `UPPER_SNAKE` strings the frontend can branch on.

## 6. Caching & performance (makes playback smooth)

Per-year responses are **immutable** until the data changes, so cache hard:
- `Cache-Control: public, max-age=86400, stale-while-revalidate=604800` on all
  `?year=`/`{slug}` GETs.
- `ETag` from a content hash (or a global `data_version` bumped on each seed load); honor
  `If-None-Match` → `304`.
- Put a CDN in front; `/state?year=1066` becomes an edge hit. Bust by changing
  `data_version` (e.g. include it in the URL or vary the ETag) on reseed.
- Server: every query is an index range scan (data-models §5). Add `gzip`/`br` compression —
  GeoJSON compresses extremely well.
- Frontend mirrors this with TanStack Query (§04 frontend) + prefetching key years.

## 7. Middleware stack (chi)

`RequestID → RealIP → slog request logger → Recoverer → CORS → gzip → Timeout(10s)` then
routes. Read-only API needs no auth for MVP; add a simple rate-limit if exposed publicly.

## 8. Versioning & evolution

- URL-versioned (`/api/v1`). Additive changes (new fields) don't bump the version; breaking
  changes do.
- The aggregate `/state` shape is the contract the frontend depends on most — extend it by
  adding keys, never repurposing existing ones.
- If you adopt OpenAPI (recommended once stable), keep `openapi.yaml` next to this doc and
  generate the frontend types from it (architecture §5).
