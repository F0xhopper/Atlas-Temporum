# Seeding — Polities

> Table: `polity` · File: `data/seed/polities.json` · Effort: **Low** · Phase: **0 (first)**

Polities are the **identity** of the political entities (kingdoms, earldoms, principalities).
Everything else references them by `slug`, so **seed these first** — nothing else loads
cleanly until the polity slugs exist. Their *borders* are NOT here; those live in
`territory_version` (see [territories.md](./territories.md)). What lives here is the stable
identity and, crucially, the **consistent colour** used across all years.

## Source

Hand-authored. There is no dataset to import — this is a short, curated list (a handful of
entities for the MVP). Pull names/dates from Wikipedia "List of …" articles or Wikidata if you
want, but typing them is faster.

MVP set (expand later): Kingdom of England, Kingdom of Scotland, Principality of Wales,
Earldom of Mercia (+ other Anglo-Saxon earldoms as you flesh out the early period).

> **MVP scope (1000–1216, see [05-seeding.md](../05-seeding.md)).** Start with just England,
> Scotland, and Wales — enough to render the map and the 1066 transition. The Anglo-Saxon
> **earldoms** (Mercia, Wessex, Northumbria, East Anglia) are the "fragmentation" refinement:
> add them to make the pre-1066 map visibly fragmented, since they dissolve into the Norman
> kingdom after the Conquest. No post-1216 polities needed for the MVP.

## Authoring format

`data/seed/polities.json` — array of objects (see [`../../data/examples/polities.json`](../../data/examples/polities.json)):

```json
{
  "slug": "kingdom-of-england",
  "name": "Kingdom of England",
  "kind": "kingdom",
  "color": "#b03a2e",
  "description": "The unified English realm; Anglo-Saxon, then Norman and Angevin.",
  "foundedYear": 927
}
```

## Field guidance

| Field | How to set it |
|------|----------------|
| `slug` | kebab-case, stable, unique. This is the join key used by territories/reigns/events. Never change it after data references it. |
| `name` | Display name. |
| `kind` | One of `kingdom \| earldom \| principality \| duchy \| lordship \| other` (docs/02 §4). |
| `color` | `#RRGGBB`. **Pick a distinct, readable palette up front** — this colour represents the polity across all 500 years, so choose for contrast on the map, not per-period. Avoid colours too close to each other. |
| `description` | One or two sentences for hover/click. |
| `foundedYear` / `dissolvedYear` | Optional informational bounds. Not used for filtering (that's what territory intervals do), just context. |

## Validation

- `slug` unique and kebab-case.
- `kind` in the enum set.
- `color` matches `^#[0-9a-fA-F]{6}$`.
- `foundedYear`/`dissolvedYear` (if present) sane and `dissolved > founded`.

## Dependencies & order

- **Depends on:** nothing.
- **Depended on by:** `territory_version`, `reign`, `event` (all reference `polity.slug`).
- Load **before** everything except possibly `person`/`city` (which are also dependency-free).

## Gotchas

- **Colour is forever.** Changing a polity's colour later silently restyles every historical
  year. Decide the palette deliberately at the start.
- **Don't encode borders or "current ruler" here.** Identity only. Borders → territories;
  rulers → reigns. Keeping this table thin is what lets a polity shrink, split, or change hands
  while staying one consistent identity.
