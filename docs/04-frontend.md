# 04 — Frontend (Next.js 16)

Next.js 16 App Router + React 19 + TypeScript + MapLibre GL JS. The whole UI is a function of
one state value, `currentYear`. This doc covers structure, the map integration (the tricky
part), state management, and each component.

## 1. Guiding principles

1. **`currentYear` is the single source of UI truth.** Territories, monarch bar, cities,
   and event markers all derive from it. Changing the year is the only
   "verb" in the core loop.
2. **The map is imperative; React is declarative — keep them on opposite sides of a wall.**
   MapLibre owns the canvas. React never re-creates the map; it pushes data into existing
   sources via `source.setData()` inside effects. Never put GeoJSON features in React state
   that re-renders the map component.
3. **Server Components for the shell, Client Components for anything interactive.** The map,
   slider, and panels are Client Components (`"use client"`). The page shell, metadata, and
   initial data fetch can be Server Components.
4. **Fetch per year, cache per year.** TanStack Query keyed by `["state", year]`. Immutable
   data → cache forever, prefetch ahead during playback.

## 2. App Router structure

```
frontend/
├── app/
│   ├── layout.tsx              # root: html/body, fonts, Providers
│   ├── page.tsx                # Server Component: loads /meta, renders <Explorer/>
│   ├── providers.tsx           # "use client": QueryClientProvider, theme
│   └── globals.css             # tailwind
├── components/
│   ├── Explorer.tsx            # "use client": top-level layout; wires map + overlays
│   ├── map/
│   │   ├── MapCanvas.tsx       # creates MapLibre map once; provides MapContext
│   │   ├── TerritoriesLayer.tsx
│   │   ├── CitiesLayer.tsx
│   │   ├── EventsLayer.tsx
│   │   └── useMapLayer.ts      # helper: add source+layer, setData on year change
│   ├── timeline/
│   │   ├── Timeline.tsx        # slider + play/pause + step + key-year snaps
│   │   └── usePlayback.ts      # requestAnimationFrame loop
│   ├── panels/
│   │   ├── MonarchBar.tsx      # top overlay
│   │   └── EventDetailPanel.tsx# right slide-in
│   ├── search/
│   │   └── SearchBox.tsx
│   └── ui/                     # buttons, panel chrome (tailwind)
├── lib/
│   ├── api.ts                  # typed fetch wrappers
│   ├── types.ts                # TS types mirroring API (architecture §5)
│   ├── queries.ts              # TanStack Query hooks (useWorldState, useEventDetail…)
│   ├── eventMeta.ts            # event_type → { icon, color, label }
│   └── mapStyle.ts             # base style + bounds from /meta
├── store/
│   └── useTimeline.ts          # Zustand: currentYear, isPlaying, selectedEventSlug
└── package.json
```

## 3. State management — two layers, kept separate

**Client/UI state → Zustand** (`store/useTimeline.ts`). Tiny, synchronous, drives everything:
```ts
type TimelineState = {
  year: number;                 // currentYear, the one source of truth
  isPlaying: boolean;
  speed: number;                // years per second during playback
  selectedEventSlug: string | null;
  setYear: (y: number) => void; // clamps to [min,max]
  play: () => void; pause: () => void; togglePlay: () => void;
  stepBy: (delta: number) => void;
  snapToKeyYear: (y: number) => void;
  selectEvent: (slug: string | null) => void;
};
```

**Server/cache state → TanStack Query** (`lib/queries.ts`). Keyed by year/slug, immutable:
```ts
export const useWorldState = (year: number) =>
  useQuery({
    queryKey: ["state", year],
    queryFn: () => api.getState(year),
    staleTime: Infinity,          // per-year data never changes
    gcTime: 30 * 60_000,
    placeholderData: keepPreviousData, // keep old frame while next loads → no flicker
  });

export const useEventDetail = (slug: string | null) =>
  useQuery({ queryKey: ["event", slug], queryFn: () => api.getEvent(slug!),
             enabled: !!slug, staleTime: Infinity });
```

Why two stores: `year` changes ~60×/sec during playback (UI concern); world data is fetched,
cached, deduped (server concern). Mixing them causes re-render storms.

## 4. MapLibre integration (the careful part)

### 4.1 Create the map exactly once
`MapCanvas.tsx` creates the `maplibregl.Map` in a `useEffect([])`, stores it in a ref, and
exposes it via context once `load` fires. It renders a single `<div>` and **never re-renders
on year change**. MapLibre is client-only → this file is `"use client"` and dynamically
imported with `ssr: false`.

```tsx
"use client";
import maplibregl from "maplibre-gl";
const MapContext = createContext<maplibregl.Map | null>(null);

export function MapCanvas({ meta, children }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const [map, setMap] = useState<maplibregl.Map | null>(null);
  useEffect(() => {
    const m = new maplibregl.Map({
      container: ref.current!, style: mapStyle(meta),
      center: [meta.defaultCenter.lng, meta.defaultCenter.lat], zoom: meta.defaultZoom,
      maxBounds: boundsToLngLat(meta.bounds),
    });
    m.on("load", () => setMap(m));
    return () => m.remove();
  }, []);                                    // <-- empty deps: created once
  return <div ref={ref} className="absolute inset-0">
    <MapContext.Provider value={map}>{map && children}</MapContext.Provider>
  </div>;
}
```

### 4.2 Layers as declarative components over imperative MapLibre
Each layer component reads `useWorldState(year)` and pushes data into its source. The
`useMapLayer` helper encapsulates the add-once / update-on-change pattern:

```ts
// add source+layer once when map ready; call source.setData when `data` changes
export function useMapLayer(id, { type, paint, layout }, data) {
  const map = useMap();
  useEffect(() => {                          // add once
    if (!map || map.getSource(id)) return;
    map.addSource(id, { type: "geojson", data });
    map.addLayer({ id, type, source: id, paint, layout });
  }, [map]);
  useEffect(() => {                          // update on year change
    const src = map?.getSource(id) as maplibregl.GeoJSONSource | undefined;
    src?.setData(data);
  }, [data]);
}
```

- **TerritoriesLayer**: `fill` layer, `fill-color` from `["get","color"]`,
  `fill-opacity ~0.5`, plus a `line` layer for borders. Smooth year-to-year change is just
  `setData`; for a cross-fade, animate `fill-opacity` over ~200ms on change.
- **CitiesLayer**: `circle` layer, `circle-radius` interpolated from `sizeRank`
  (`["interpolate",["linear"],["get","sizeRank"],1,4,5,20]`). Because the API can return
  fractional `sizeRank` (lerp mode, API §3.2), circles **grow smoothly** as the year advances.
- **EventsLayer**: `symbol` layer with text/emoji icons keyed by `event_type` (from
  `eventMeta.ts`), or `circle` + DOM markers for richer icons. Click → `selectEvent(slug)`.
  Optional fade-in using `icon-opacity` when `window>0` (API §3.3).

### 4.3 Interactions
- Click event marker → Zustand `selectEvent(slug)` → `EventDetailPanel` opens and
  `useEventDetail(slug)` fetches the body; map `flyTo` the point; highlight via a feature-state
  or a dedicated "selected" layer.
- Hover territory/city → popup with name (`map.on("mousemove", layerId, …)`).

## 5. The timeline (main control)

`Timeline.tsx` (bottom, full width):
- **Slider** `min=1000 max=1500 step=1` bound to Zustand `year`. Throttle `setYear` to one
  call per animation frame so dragging doesn't fire 100s of fetches; TanStack Query +
  `keepPreviousData` ensures the visible frame only swaps when the new year's data arrives.
- **Play/Pause** → `usePlayback`: a `requestAnimationFrame` loop advancing `year` by
  `speed` years/sec; pause at `max`. While playing, **prefetch** `year+1` (and key years)
  via `queryClient.prefetchQuery` so frames are ready.
- **Step ◀ ▶** → `stepBy(±1)`.
- **Key-year snaps** → tick marks at `meta.keyYears`; clicking snaps + can pulse a highlight.
- Show the current year prominently (e.g. large "1066" label).

```ts
// usePlayback.ts (essence)
useEffect(() => {
  if (!isPlaying) return;
  let raf = 0, last = performance.now();
  const tick = (t: number) => {
    const dy = ((t - last) / 1000) * speed; last = t;
    const next = Math.min(max, year + dy);
    setYear(Math.round(next));
    queryClient.prefetchQuery({ queryKey: ["state", Math.round(next) + 1], queryFn: ... });
    if (next >= max) return pause();
    raf = requestAnimationFrame(tick);
  };
  raf = requestAnimationFrame(tick);
  return () => cancelAnimationFrame(raf);
}, [isPlaying, speed]);
```

## 6. Overlay panels (each is a pure function of data)

| Component | Position | Source | Shows |
|----------|----------|--------|-------|
| `MonarchBar` | top | `worldState.monarchs` | "👑 King: William I (1066–1087)"; flags disputes |
| `EventDetailPanel` | right (slide-in) | `useEventDetail(selectedEventSlug)` | name, date, location, description, outcome, key figures |
| `SearchBox` | top-right | `GET /search` | jump-to results |

All read from the **same** `useWorldState(year)` (except the detail panel, which lazy-loads).
They are dumb/presentational — no fetching logic beyond the shared hooks.

### Search behavior
On submit/typeahead → `GET /search?q=`. Selecting a result:
1. `setYear(result.year)` (snap timeline),
2. `map.flyTo({ center: [lng, lat] })`,
3. if `kind==="event"` → `selectEvent(result.slug)` (opens panel + highlights marker).

## 7. Data fetching & SSR strategy

- `app/page.tsx` (Server Component) fetches `/meta` (and optionally the initial `/state` for
  the default year) and passes as props → fast first paint, no client waterfall for config.
- The map and per-year data are **client-fetched** (MapLibre is client-only anyway).
- Deep links: read `?year=` and `?event=` from the URL on load to set initial Zustand state;
  write them back on change (shallow `router.replace`) so any frame is shareable.
- Next.js 16 niceties to use: `loading.tsx` for the shell skeleton, route-level
  `metadata`, and `dynamic(() => import("./MapCanvas"), { ssr: false })` for the map.

## 8. Performance checklist

- One MapLibre map instance; update via `setData`, never re-mount.
- Throttle slider → one `setYear` per frame; `keepPreviousData` to avoid flicker.
- Prefetch `year+1` and all `keyYears` on idle/playback.
- Hard-cache responses (API §6) → most slider moves are warm cache or `304`.
- Simplify territory geometry server-side or in the seed step (`ST_SimplifyPreserveTopology`)
  so polygons are light over the wire; ship coarser geometry at low zoom if needed.
- gzip/br on the wire (handled by the API / CDN).

## 9. Component → data dependency map (quick reference)

```
currentYear (Zustand)
   └─ useWorldState(year)  ──► TerritoriesLayer (territories FC)
                            ──► CitiesLayer       (cities FC)
                            ──► EventsLayer        (events FC)
                            ──► MonarchBar         (monarchs[])
selectedEventSlug (Zustand)
   └─ useEventDetail(slug) ──► EventDetailPanel
search query
   └─ GET /search          ──► SearchBox ──► setYear + flyTo + selectEvent
```

Everything traces back to `currentYear`. That is the whole app.
