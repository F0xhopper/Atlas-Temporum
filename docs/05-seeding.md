# 05 — Seeding Plan

How the database gets its data. This is the index; each **main entity has its own seeding
doc** under [`seeding/`](./seeding/) with sources, authoring format, field-by-field guidance,
validation, and gotchas.

| # | Entity | Doc | Tables seeded | Effort | Phase |
|---|--------|-----|---------------|--------|-------|
| 1 | Polities | [seeding/polities.md](./seeding/polities.md) | `polity` | Low | 0 |
| 2 | Monarchs | [seeding/monarchs.md](./seeding/monarchs.md) | `person`, `reign` | Low | 0 |
| 3 | Events | [seeding/events.md](./seeding/events.md) | `event`, `event_participant` | Medium | 0 |
| 4 | Cities & Population | [seeding/cities.md](./seeding/cities.md) | `city`, `population_sample` | Low–Med | 0 |
| 5 | Territories | [seeding/territories.md](./seeding/territories.md) | `territory_version` | **High** | 0 (placeholder) → 1 (real) |

## MVP period scope: **1000–1216, the Norman period** (read this first)

The schema spans the full **1000–1500**, but the MVP only **seeds data densely for
1000–1216** — late Anglo-Saxon England, the Norman Conquest, the Anarchy, and Magna Carta.
Everything outside this window is a later-expansion concern; don't author it yet.

**Why this window:**
- It maximises the headline feature. The most dramatic *territorial* change in the whole range
  is here: fragmented Anglo-Saxon earldoms + independent Scotland/Wales → 1066 conquest →
  consolidated Norman kingdom. Sliding produces visible change (later medieval England is a
  fairly static unified realm by comparison).
- Two world-famous bookends: **Hastings (1066)** and **Magna Carta (1215)**.
- Mid-window drama that also exercises `is_disputed`: **the Anarchy (1135–1154)**.
- Bounded scope: ~10 reigns, a handful of polities, and only ~5–6 territory snapshots.

**Anchor years to author** (use for `/meta.keyYears` and territory versions):

| Year | What it captures |
|------|------------------|
| 1000 | Late Anglo-Saxon England (fragmented earldoms) + Scotland + Wales |
| 1066 | Norman Conquest — the pivotal transition |
| 1086 | Domesday; consolidated Norman kingdom |
| 1135 | Start of the Anarchy (contested control) |
| 1154 | Henry II; realm reunified, Angevin period begins |
| 1215 | Magna Carta |

**Set the slider to the window.** For the MVP, set `/meta.yearRange` to `{min:1000, max:1216}`
so the timeline matches the seeded data and there are no empty years. Widen it later as you
extend the data.

**Per-entity scope** is noted in each seeding doc under its own "MVP scope" heading.

**Levers:** leaner → cut to **1000–1100** (Conquest century only, ~3 snapshots). Richer
(post-MVP) → extend to **1300** (adds the 1284 Welsh annexation) or the full **1500** (Black
Death, Wars of the Roses, Bosworth).

## 1. Philosophy (read first)

- **Files are the source of truth.** Author everything as version-controlled files in
  `data/seed/`. One Go loader (`cmd/seed`) loads them into Postgres. Never hand-edit the DB.
- **The loader is dumb and idempotent.** Re-running it always yields the same DB. For a
  read-only MVP, wrap the whole load in a transaction that `TRUNCATE`s and reinserts.
- **Design wide, seed narrow.** The full schema exists (docs/02), but you seed in phases.
  Phase 0 gets a working app fast with easy tabular data + placeholder geometry; Phase 1
  invests in real territory borders. See each doc's "Phase" note.
- **Validate before you load.** Geometry validity, unique slugs, year bounds, FK references —
  all checked before touching the DB (§4). Bad data fails loudly, not silently.

## 2. Where the data comes from (summary; details per doc)

| Need | Primary source | License |
|------|----------------|---------|
| Territory borders | [`aourednik/historical-basemaps`](https://github.com/aourednik/historical-basemaps) | CC-BY-SA |
| Modern coastline / basemap | [Natural Earth](https://www.naturalearthdata.com) | Public domain |
| Monarchs, reigns, houses | [Wikidata](https://query.wikidata.org) (SPARQL) | CC0 |
| Event facts, dates, coords | Wikidata + Wikipedia | CC0 / CC-BY-SA |
| City coordinates | Wikidata / [GeoNames](https://www.geonames.org) | CC0 / CC-BY |
| City relative size, narrative | Hand-authored from historical references | — |

**Keep a `data/SOURCES.md`** crediting each dataset + license. The CC-BY-SA on borders means
attribution + share-alike is required — track it from day one.

## 3. Recommended order

Seed in **dependency order** (FKs resolve), which also happens to be **impact/effort order**:

```
1. polities          (no deps; everything references these by slug)
2. monarchs          (person → reign → polity)         ← highest value / lowest effort
3. cities            (no deps) + population (→ city)
4. events            (→ city?, → polity?) + participants (→ person)
5. territories       (→ polity)  ← placeholders in Phase 0, real borders in Phase 1
```

Rationale (see the conversation that produced this plan): monarchs/events/cities are cheap
tabular data that light up the timeline, panels, and search immediately. Territories are the
highest-*impact* but highest-*effort* feature, so they start as placeholders and you invest in
real geometry last, without ever being blocked.

## 4. Validation gate (runs in CI and in the loader)

Before any insert:

- **Slugs** unique within each entity, kebab-case, stable.
- **Years** ∈ `[1000, 1500]`; intervals satisfy `valid_to > valid_from` / `reign_to > reign_from`.
- **FK references** (every `politySlug`, `personSlug`, `citySlug`) resolve to a known slug.
- **Geometry** parses, is valid (`ST_IsValid`; auto-`ST_MakeValid`), SRID 4326, winding correct.
- **Enums** (`kind`, `type`, `role`) are from the allowed sets (docs/02 §4).

Author JSON Schemas under `data/seed/schema/` and run them in CI so bad data never merges.

## 5. The loader (`cmd/seed`)

```
read files → validate → BEGIN tx
  → upsert polity, person, city            (identity, by slug)
  → resolve slug→id maps in memory
  → insert territory_version, reign, event (reference identities)
  → insert event_participant, population_sample
  → bump data_version                       (cache-bust / ETag)
COMMIT
```

Idempotent (truncate-and-reload or `ON CONFLICT (slug) DO UPDATE`). The loader is the only
writer; the API is read-only for MVP. Geometry is read from GeoJSON files with
`ST_GeomFromGeoJSON`, simplified with `ST_SimplifyPreserveTopology`, and stored as native
`geometry` (never as raw JSON text — see [seeding/territories.md](./seeding/territories.md)).

## 6. `data/seed/` layout

```
data/seed/
├── polities.json
├── persons.json
├── reigns.json
├── cities.json
├── population.json
├── events.json
├── territories/
│   ├── kingdom-of-england.geojson
│   ├── kingdom-of-scotland.geojson
│   └── ...
└── schema/                 # JSON Schemas for the validation gate
```

Working fixtures matching these shapes already live in [`../data/examples/`](../data/examples/).
