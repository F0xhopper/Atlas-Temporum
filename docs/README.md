# Atlas Temporum — Design Documentation

> Interactive map of Medieval Britain (1000–1500 AD). "Slide through time and watch
> medieval Britain change." Everything is driven by **one** control: the timeline year.

This folder is the source of truth for the MVP design. Read in order:

| Doc | What it covers |
|-----|----------------|
| [01-architecture.md](./01-architecture.md) | System shape, tech stack, repo layout, data flow, the "year → state" core abstraction |
| [02-data-models.md](./02-data-models.md) | Domain model, temporal strategy, PostGIS schema, Go structs, validation, seed format |
| [03-api.md](./03-api.md) | REST endpoints, the `GET /state?year=` aggregate, GeoJSON contracts, caching, errors |
| [04-frontend.md](./04-frontend.md) | Next.js 16 App Router structure, MapLibre integration, state management, components |

## The one idea to keep in your head

Every feature is a **projection of the domain at a given `year`**. The frontend holds a
single piece of authoritative UI state — `currentYear` — and the entire screen
(territories, monarch, cities, events, summary) is a pure function of it:

```
render(year) = territories(year)
             + monarch(year)
             + cities(year)
             + events(year)
             + summary(year)
```

The backend mirrors this: the headline endpoint is `GET /api/v1/state?year=1215`, which
returns everything needed to draw one frame. Design every model so that "what was true in
year Y?" is a cheap, indexable query.

## Tech stack (decided)

- **Backend:** Go (net/http + chi router), PostgreSQL 16 + PostGIS 3.4, `sqlc` for typed queries, `goose` for migrations.
- **Frontend:** Next.js 16 (App Router, React 19), TypeScript, MapLibre GL JS, Zustand for client state, TanStack Query for server cache.
- **Data:** Authoring in versioned GeoJSON/JSON seed files → loaded into Postgres. Files are the human-editable source; DB is the queryable runtime store.

## Scope guardrails (MVP)

In scope: timeline, territories, monarchs, events + detail panel, cities/population, year
summaries, basic search. Out of scope for v1: user accounts, editing UI, real population
numbers, continental Europe detail, polygon morphing/interpolation between border versions
(we **snap** instead).
