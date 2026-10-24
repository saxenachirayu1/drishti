# Labelling guide (B-06)

One GeoJSON file per pilot city, named as in `configs/cities.yaml` (for example `pune.geojson`).
Coordinates in EPSG:4326 (longitude, latitude). Target: **150+ `waste` polygons per city**, plus hard negatives.

## Each feature

```json
{
  "type": "Feature",
  "geometry": { "type": "Polygon", "coordinates": [[[73.85, 18.52], [73.851, 18.52], [73.851, 18.521], [73.85, 18.52]]] },
  "properties": { "label": "waste", "source": "https://link-to-news-or-municipal-list", "seen": "2026-10" }
}
```

`label` must be one of:

| Label | Use it for |
| --- | --- |
| `waste` | Open dumps, legacy landfills, riverbank and lake dumping, burnt waste heaps |
| `construction` | Active building sites, debris piles that are clearly part of a construction site |
| `bare_soil` | Empty plots, dry fields, dirt grounds |
| `quarry` | Quarries and mining pits |
| `industrial` | Factory yards, scrap yards, container depots |
| `other` | Anything else that looks like waste but is not |

Negatives matter as much as positives: they teach the model what *not* to flag.

## How to draw

1. Open QGIS (or Google Earth Pro) with a high-resolution basemap and the latest Sentinel-2 true-colour image of the city.
2. Start from known sites: news reports, municipal legacy-dumpsite lists, places you have seen yourself. Put the link or note in `source`.
3. Trace the outer edge of the dumped material, not the plot boundary. Skip sites smaller than about 30 m x 30 m: Sentinel-2 cannot see them.
4. For each city, add at least as many negatives as positives, spread across the city.
5. Check the date: the polygon must match imagery from the same season you train on (`seen`).

## Check before committing

```bash
python -m drishti_pipeline.cli labels-check labels/pune.geojson
```

It validates every feature and prints counts per label and whether the 150-positive target is met.
