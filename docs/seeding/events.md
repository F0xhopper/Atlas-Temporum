# Seeding — Events (+ Participants)

> Tables: `event`, `event_participant` · File: `data/seed/events.json`
> Effort: **Medium** · Phase: **0**

Events are the educational core: clickable markers that open the detail panel ("click Hastings,
learn what happened"). They also feed search. This is the one entity where you **hand-author
the narrative** — and that's correct, because it's a small, high-value set (~30–50 events for
the MVP) and you want editorial control over the descriptions.

## Source — Wikidata for facts, Wikipedia for prose

- **Wikidata** for the structured bits: date (`point in time` P585), coordinates (P625),
  participants. Good for battles and treaties.
- **Wikipedia** article for the human-written `description`, `outcome`, and key-figure roles.

Don't scrape — curate. Author the marquee events first (Hastings 1066, Magna Carta 1215, Black
Death 1348, Wars of the Roses battles, Bosworth 1485), then fill in. Working examples:
[`../../data/examples/events.json`](../../data/examples/events.json).

## Authoring format

`events.json` — array; participants are nested for authoring convenience and split into
`event_participant` by the loader:

```json
{
  "slug": "battle-of-hastings",
  "title": "Battle of Hastings",
  "type": "battle",
  "year": 1066,
  "dateStart": "1066-10-14",
  "dateDisplay": "14 October 1066",
  "isCirca": false,
  "lng": 0.4876, "lat": 50.9116,
  "citySlug": "hastings",
  "politySlug": "kingdom-of-england",
  "summary": "Decisive Norman victory over the Anglo-Saxons.",
  "description": "Duke William of Normandy defeated King Harold II ...",
  "outcome": "Norman victory; William crowned King of England on 25 December 1066.",
  "importance": 5,
  "participants": [
    { "personSlug": "william-i", "role": "victor" },
    { "personSlug": "harold-godwinson", "role": "defeated" }
  ]
}
```

## Field guidance

| Field | How to set it |
|------|----------------|
| `type` | `battle\|coronation\|treaty\|law\|rebellion\|disease\|castle\|other` — drives the marker icon (mapping lives in `frontend/lib/eventMeta.ts`, not the DB). |
| `year` | **The filter key** (integer). For ranged events (plague), use the start year here and `dateEnd` for the span. |
| `dateStart` / `dateEnd` | ISO or fuzzy. `dateEnd` for sieges/plagues spanning years. |
| `dateDisplay` | Human string shown in the panel: "14 October 1066", "1348–1350". |
| `isCirca` | `true` for uncertain dates → UI renders "c.". |
| `lng` / `lat` | Point location. **May be omitted** for non-spatial events (a national law) — those won't get a map marker but remain searchable. |
| `citySlug` | Optional link to a city (resolved to `city_id`). |
| `politySlug` | Optional associated state. |
| `summary` | One-liner for the marker tooltip / list row. (This is the *event* summary — distinct from the removed year-summary feature.) |
| `description` / `outcome` | Full body for the detail panel. |
| `importance` | 1–5. Drives marker prominence and lets the client show only major events when zoomed out. Reserve 5 for the truly pivotal. |
| `participants[].role` | Free text: "victor", "defeated", "signatory", "monarch". Powers the panel's "Key figures" and person-based search. |

## Validation

- `slug` unique; `type` and any `role` sane.
- `year` ∈ [1000,1500]; if `dateEnd` present, its year ≥ `year`.
- Every `personSlug` (participants), `citySlug`, `politySlug` resolves.
- `importance` ∈ [1,5].
- If `lng`/`lat` present, both present and within the map bounds.

## Dependencies & order

- **Depends on:** `person` (participants), `city` (optional), `polity` (optional).
- Load **after** persons and cities so FKs resolve. `event_participant` rows are derived from
  the nested `participants` during load.

## Gotchas

- **Null geometry is fine.** Laws/treaties without a place are valid events — exclude them from
  the map FeatureCollection but keep them searchable.
- **Ranged events.** Decide how a multi-year event (plague 1348–1350) appears as the slider
  moves: present across `[dateStart.year, dateEnd.year]`. The API `window` param also lets
  point events fade in near their year (docs/03 §3.3).
- **Don't confuse the two `summary` concepts.** `event.summary` is a per-event one-liner and
  stays. The standalone year-summary panel was removed from the plan.
