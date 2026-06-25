# 02 — Data Models

The hardest and most important part of this app is **temporal modeling**: the world is not
static, it has a *state at every year*. Get this right and every feature falls out cheaply.

## 1. Modeling principles

1. **Separate stable identity from time-varying facets.** A kingdom (`Polity`) is one thing
   that persists; its *borders* change. A city persists; its *population* changes. Model the
   identity once, then attach time-sliced rows for the parts that vary.
2. **Valid-time intervals, half-open `[valid_from, valid_to)`.** Every time-varying row says
   *when it was true*. `valid_to = NULL` means "still true at end of our window (1500)".
   Half-open intervals make adjacency clean: a reign ending in 1087 and the next starting in
   1087 never overlap or gap.
3. **Year granularity for state, precise dates for display.** All "valid at year Y" queries
   use integer years. Events carry an extra precise/fuzzy date only for showing to users.
4. **Snap, don't morph.** Between two border versions we do **not** interpolate polygons
   (polygon morphing is hard and historically dishonest). The map shows the version valid at
   the current year and snaps when crossing a boundary. This is a deliberate MVP decision.
5. **Stable slugs for everything user-facing.** `battle-of-hastings`, `kingdom-of-england`,
   `london`. Slugs power deep links and search; the integer PK is internal.
6. **Let PostGIS own geometry.** Store `geometry(...,4326)`; emit GeoJSON with
   `ST_AsGeoJSON`. The frontend never computes geometry.

## 2. Entity map (ERD)

```
                ┌───────────┐
                │  Polity   │ (identity: a kingdom/state/realm)
                └─────┬─────┘
       ┌──────────────┼───────────────────┐
       │ 1:N          │ 1:N               │ 1:N
┌──────▼───────┐ ┌────▼──────┐      ┌──────▼──────┐
│TerritoryVer- │ │  Reign    │      │ (events ref │
│sion (geom +  │ │ (ruler ×  │      │  a polity,  │
│ valid range) │ │ polity ×  │      │  optional)  │
└──────────────┘ │ validrng) │      └─────────────┘
                 └────┬──────┘
                      │ N:1
                 ┌────▼──────┐
                 │  Person   │ (monarchs & event figures)
                 └────┬──────┘
                      │ M:N (event_participant)
                 ┌────▼──────┐        ┌──────────────┐
                 │  Event    │───────►│   City       │ (optional location ref)
                 │ (point +  │  N:1?  │ (settlement) │
                 │  date/yr) │        └──────┬───────┘
                 └───────────┘               │ 1:N
                                       ┌──────▼─────────┐
                                       │ PopulationSam- │
                                       │ ple (yr × size)│
                                       └────────────────┘
```

## 3. The entities

For each: purpose, fields, temporal treatment, and notes. SQL DDL is in §5, Go structs in §6.

### 3.1 Polity — political entity (identity)
The stable identity of a state/kingdom/realm. Its **borders live in `TerritoryVersion`**, not
here.

| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | internal |
| `slug` | text unique | `kingdom-of-england`, `earldom-of-mercia` |
| `name` | text | display name |
| `kind` | enum | `kingdom` \| `earldom` \| `principality` \| `lordship` \| `duchy` \| `other` |
| `color` | text (hex) | base fill color; territory versions inherit unless overridden |
| `description` | text | short blurb for hover/click |
| `founded_year` / `dissolved_year` | int null | lifespan bounds (informational) |

Why separate from geometry: a polity can shrink, split, merge, or be conquered while keeping
the same identity and color across years. Consistent color over time is a UX must.

### 3.2 TerritoryVersion — a polity's borders during an interval (time-varying geometry)
The heart of the territories layer. One row = "this polity controlled *this shape* from
`valid_from` until `valid_to`".

| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | |
| `polity_id` | FK → polity | |
| `geom` | `geometry(MultiPolygon, 4326)` | the controlled area |
| `valid_from` | int (year) | inclusive |
| `valid_to` | int (year) null | exclusive; NULL = through 1500 |
| `color_override` | text null | rare; defaults to polity color |
| `confidence` | enum `attested`\|`approximate`\|`disputed` | honesty about source quality |
| `note` | text null | e.g. "borders highly uncertain" |

Temporal model: **half-open year interval**. "Territories at year Y" =
`valid_from <= Y AND (valid_to IS NULL OR valid_to > Y)`. Authoring tip: you only create a new
version when borders *meaningfully* change (1000, 1016, 1066, 1086, 1135, 1154, 1284, 1296,
1455, 1471, 1485…). Most years reuse a version — the slider snaps.

> **MVP simplification:** if full polygon authoring per period is too much work to start,
> ship a coarser variant: a small set of **whole-map snapshots** (one MultiPolygon-per-polity
> FeatureCollection per key year) and have the API pick the latest snapshot `<= year`. The
> `TerritoryVersion` model above is the same idea normalized; start coarse, refine later.

### 3.3 Person — monarchs and historical figures
Unify rulers and event figures into one table; a person can be both (e.g. William I rules
*and* appears in "Battle of Hastings").

| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | |
| `slug` | text unique | `william-i`, `john-king-of-england` |
| `name` | text | "William I" |
| `epithet` | text null | "the Conqueror" |
| `house` | text null | dynasty: "Normandy", "Plantagenet", "Lancaster", "York" |
| `birth_year` / `death_year` | int null | fuzzy ok |
| `bio` | text null | short |

### 3.4 Reign — a person rules a polity over an interval (the Monarch feature)
This is what powers the top monarch bar. A reign is the join of *who*, *over what*, *when*.

| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | |
| `person_id` | FK → person | the ruler |
| `polity_id` | FK → polity | what they ruled (usually Kingdom of England) |
| `title` | text | "King of England", "King of Scots" |
| `reign_from` | int (year) | inclusive |
| `reign_to` | int (year) null | exclusive; NULL = beyond window |
| `reign_from_date` / `reign_to_date` | text null | precise/fuzzy display: `1066-12-25` |
| `is_disputed` | bool | for civil-war periods (multiple "kings" at once) |

"Monarch at year Y for polity P" = reign where `reign_from <= Y < reign_to`. Note this can
return **more than one** during disputed periods (Wars of the Roses) — the UI shows the
primary and flags dispute. Don't assume a single reign per year.

### 3.5 Event — point-located historical event (markers + detail panel)
| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | |
| `slug` | text unique | `battle-of-hastings`, `magna-carta` |
| `title` | text | "Battle of Hastings" |
| `type` | enum | `battle`\|`coronation`\|`treaty`\|`law`\|`rebellion`\|`disease`\|`castle`\|`other` |
| `year` | int | **the filtering key** (snap year) |
| `date_start` | text null | ISO or fuzzy: `1066-10-14` |
| `date_end` | text null | for multi-day/year events (sieges, plague) |
| `date_display` | text | human string: "14 October 1066", "1348–1350" |
| `is_circa` | bool | uncertain date → render "c." |
| `geom` | `geometry(Point, 4326)` null | location; may be null for non-spatial laws |
| `city_id` | FK → city null | if it happened at/near a known city |
| `polity_id` | FK → polity null | associated state |
| `summary` | text | one-liner for the marker tooltip/list |
| `description` | text | full body for the detail panel |
| `outcome` | text null | "Norman victory; William becomes king" |
| `importance` | smallint (1–5) | drives marker prominence & default visibility |

Temporal model for events: **events filter by `year`** (and an optional ± window so a marker
can "fade in" near its year — see API §3.3). For ranged events (plague 1348–1350) store
`date_start`/`date_end` years and treat the event as present across that span.

Key figures of an event → `event_participant` (§3.6).

### 3.6 EventParticipant — M:N event ↔ person
| Field | Type |
|------|------|
| `event_id` | FK → event |
| `person_id` | FK → person |
| `role` | text — "victor", "defeated", "signatory", "monarch" |
| PK | (event_id, person_id) |

Lets the detail panel list "Key figures" and lets search find events by person.

### 3.7 City — settlement (identity)
| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | |
| `slug` | text unique | `london`, `york` |
| `name` | text | |
| `geom` | `geometry(Point, 4326)` | location (cities don't move) |
| `founded_year` | int null | render only after founding |
| `description` | text null | |

### 3.8 PopulationSample — a city's relative size at a year (the growth animation)
Do **not** store one "population" on the city. Store samples and let the API pick/interpolate.

| Field | Type | Notes |
|------|------|------|
| `id` | bigint PK | |
| `city_id` | FK → city | |
| `year` | int | sample year |
| `size_rank` | smallint (1–5) | **relative importance**, NOT a real headcount |

Per the brief: circle size = relative importance, real numbers never shown. Store sparse
samples (e.g. London: 1000→3, 1100→4, 1300→5, 1350→4 post-plague, 1500→5). The API returns,
for a query year, the **most recent sample ≤ year** (step) or a smooth interpolation between
the bracketing samples (lerp) for nicer growth animation — your choice; see API §3.2.

## 4. Enumerations (single source of truth)

Define these as Postgres enums **and** mirror in Go/TS. Keep names identical across all three.

```
polity_kind:   kingdom | earldom | principality | duchy | lordship | other
event_type:    battle | coronation | treaty | law | rebellion | disease | castle | other
confidence:    attested | approximate | disputed
```

Frontend maps `event_type` → icon (⚔ 👑 📜 📜 🔥 ☠ 🏰) and color. Keep that mapping in
`frontend/lib/eventMeta.ts`, never in the DB.

## 5. PostgreSQL + PostGIS schema (DDL)

See [examples/schema.sql](../data/examples/schema.sql) for the full runnable file. Highlights:

```sql
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TYPE polity_kind AS ENUM ('kingdom','earldom','principality','duchy','lordship','other');
CREATE TYPE event_type  AS ENUM ('battle','coronation','treaty','law','rebellion','disease','castle','other');
CREATE TYPE confidence  AS ENUM ('attested','approximate','disputed');

CREATE TABLE polity (
  id            BIGGENERATED-... ,         -- see file (GENERATED ALWAYS AS IDENTITY)
  slug          TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL,
  kind          polity_kind NOT NULL DEFAULT 'kingdom',
  color         TEXT NOT NULL,             -- '#RRGGBB'
  description   TEXT NOT NULL DEFAULT '',
  founded_year  INT, dissolved_year INT
);

CREATE TABLE territory_version (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  polity_id   BIGINT NOT NULL REFERENCES polity(id) ON DELETE CASCADE,
  geom        geometry(MultiPolygon, 4326) NOT NULL,
  valid_from  INT NOT NULL,
  valid_to    INT,                          -- NULL = open (through 1500)
  color_override TEXT,
  confidence  confidence NOT NULL DEFAULT 'approximate',
  note        TEXT,
  CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE INDEX territory_geom_gix ON territory_version USING GIST (geom);
CREATE INDEX territory_valid_ix ON territory_version (valid_from, valid_to);

-- person, reign, event, event_participant, city, population_sample
-- ... (full DDL in data/examples/schema.sql)
```

### Indexing strategy (this is what makes the slider instant)
- **GIST** on every geometry column (`territory_version.geom`, `event.geom`, `city.geom`).
- **B-tree** on `(valid_from, valid_to)` for territory; `(reign_from, reign_to)` for reign;
  `year` for `event` and `population_sample`.
- Unique on every `slug`.
- The "state at year" queries are all index-range scans; no full scans even with thousands of
  rows.

### Temporal query patterns (copy/paste mental models)
```sql
-- Territories valid at :year  (returns GeoJSON FeatureCollection via aggregation)
SELECT p.slug, COALESCE(tv.color_override, p.color) AS color, ST_AsGeoJSON(tv.geom)
FROM territory_version tv JOIN polity p ON p.id = tv.polity_id
WHERE tv.valid_from <= :year AND (tv.valid_to IS NULL OR tv.valid_to > :year);

-- Monarch(s) ruling at :year
SELECT pe.name, pe.epithet, r.title, r.reign_from, r.reign_to, r.is_disputed
FROM reign r JOIN person pe ON pe.id = r.person_id
WHERE r.reign_from <= :year AND (r.reign_to IS NULL OR r.reign_to > :year);

-- Events in :year (exact) or within ±:window
SELECT * FROM event
WHERE :year BETWEEN year - :window AND year + :window;  -- window=0 for exact

-- City size at :year: most-recent sample <= year
SELECT DISTINCT ON (city_id) city_id, size_rank
FROM population_sample WHERE year <= :year
ORDER BY city_id, year DESC;
```

## 6. Go domain structs

Hand-written domain types in `backend/internal/domain`. `sqlc` generates row structs; these
are the clean domain/DTO layer the API returns. Keep JSON tags = API field names (camelCase).

```go
package domain

type PolityKind string
type EventType  string
type Confidence string

type Polity struct {
    ID          int64      `json:"-"`
    Slug        string     `json:"slug"`
    Name        string     `json:"name"`
    Kind        PolityKind `json:"kind"`
    Color       string     `json:"color"`
    Description string     `json:"description,omitempty"`
}

// Returned inside the territories FeatureCollection as feature.properties
type TerritoryProps struct {
    PolitySlug string     `json:"politySlug"`
    Name       string     `json:"name"`
    Color      string     `json:"color"`
    Kind       PolityKind `json:"kind"`
    Confidence Confidence `json:"confidence"`
}

type Monarch struct {
    PersonSlug string `json:"personSlug"`
    Name       string `json:"name"`
    Epithet    string `json:"epithet,omitempty"`
    House      string `json:"house,omitempty"`
    Title      string `json:"title"`
    ReignFrom  int    `json:"reignFrom"`
    ReignTo    *int   `json:"reignTo,omitempty"`
    IsDisputed bool   `json:"isDisputed"`
}

type EventProps struct {
    Slug        string    `json:"slug"`
    Title       string    `json:"title"`
    Type        EventType `json:"type"`
    Year        int       `json:"year"`
    DateDisplay string    `json:"dateDisplay"`
    IsCirca     bool      `json:"isCirca"`
    Summary     string    `json:"summary"`
    Importance  int       `json:"importance"`
    CitySlug    string    `json:"citySlug,omitempty"`
}

// Full event for the detail panel (GET /events/{slug})
type EventDetail struct {
    EventProps
    Description  string       `json:"description"`
    Outcome      string       `json:"outcome,omitempty"`
    Participants []Participant `json:"participants"`
    Lng, Lat     *float64     `json:"-"` // geometry returned via the FeatureCollection
}

type Participant struct {
    PersonSlug string `json:"personSlug"`
    Name       string `json:"name"`
    Role       string `json:"role"`
}

type CityProps struct {
    Slug     string `json:"slug"`
    Name     string `json:"name"`
    SizeRank int    `json:"sizeRank"` // 1..5, resolved for the query year
}

// The aggregate the slider fetches
type WorldState struct {
    Year        int                       `json:"year"`
    Territories FeatureCollection         `json:"territories"` // Polygon features
    Cities      FeatureCollection         `json:"cities"`      // Point features
    Events      FeatureCollection         `json:"events"`      // Point features
    Monarchs    []Monarch                 `json:"monarchs"`
}
```

`FeatureCollection`/`Feature` are thin GeoJSON wrappers in `internal/geojson` whose
`Properties` field holds the `*Props` structs above. Build geometry server-side with
`ST_AsGeoJSON` and assemble the FeatureCollection in Go (or fully in SQL with
`json_build_object` + `ST_AsGeoJSON` — see API §4 for the all-SQL approach).

## 7. Authoring pipeline (files → DB)

1. **Author** in `data/seed/`:
   - `polities.json`, `persons.json`, `reigns.json`, `events.json`, `cities.json`,
     `population.json`
   - `territories/*.geojson` — one FeatureCollection per polity (or per period). Each feature's
     `properties` carry `politySlug`, `validFrom`, `validTo`, `confidence`.
2. **Validate** with a schema (JSON Schema in `data/seed/schema/`) in CI: slugs unique, years
   in `[1000,1500]`, geometry valid (`ST_IsValid`), no reign/territory interval overlaps for
   the same polity beyond what's intended.
3. **Load** via `go run ./cmd/seed`: truncate + upsert by slug, reproject/validate geometry,
   `ST_MakeValid` as a safety net. Idempotent so re-running is safe.
4. The seed loader is the *only* writer; the API is read-only for MVP.

See [examples/](../data/examples/) for `polities.json`, `events.json`, `territories.geojson`,
`world_state.json` (a sample API response), and `schema.sql`.

## 8. Decisions to confirm before coding

These are judgment calls baked into the model above — flag if you disagree:

1. **Snap vs interpolate territories** → snap (no polygon morphing) for MVP. ✔ recommended.
2. **City size = `size_rank` 1–5**, step or lerp between samples → start with **lerp** for a
   nice grow animation, data stored as steps. ✔
3. **Disputed periods can return multiple monarchs** → model supports it; UI shows primary +
   "disputed" badge. ✔
4. **Events filter by integer `year`** with a configurable ± window for fade-in (default 0).

If any of these should differ, change here first — the API and frontend docs depend on them.
