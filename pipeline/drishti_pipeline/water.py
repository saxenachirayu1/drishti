"""B-17: is a site within 200 m of a river, canal or lake? Water features come from OpenStreetMap."""

from __future__ import annotations

from shapely.geometry import LineString, Polygon
from shapely.geometry.base import BaseGeometry
from shapely.strtree import STRtree

from . import config
from .geo import to_metric


def overpass_query(bbox: tuple[float, float, float, float]) -> str:
    w, s, e, n = bbox
    area = f"({s},{w},{n},{e})"
    return (
        "[out:json][timeout:120];("
        f'way["natural"="water"]{area};'
        f'relation["natural"="water"]{area};'
        f'way["waterway"~"^(river|canal|riverbank|stream|drain)$"]{area};'
        ");out geom;"
    )


def parse_overpass(data: dict) -> list[BaseGeometry]:
    """Turn Overpass `out geom` JSON into shapely geometries in EPSG:4326."""
    geoms: list[BaseGeometry] = []

    def coords(geometry):
        return [(p["lon"], p["lat"]) for p in geometry]

    for el in data.get("elements", []):
        if el.get("type") == "way" and len(el.get("geometry", [])) >= 2:
            pts = coords(el["geometry"])
            is_area = el.get("tags", {}).get("natural") == "water" and pts[0] == pts[-1] and len(pts) >= 4
            geoms.append(Polygon(pts) if is_area else LineString(pts))
        elif el.get("type") == "relation":
            for m in el.get("members", []):
                if m.get("role") == "outer" and len(m.get("geometry", [])) >= 2:
                    geoms.append(LineString(coords(m["geometry"])))   # outline is enough for distance
    return [g for g in geoms if g.is_valid and not g.is_empty]


def fetch_water(bbox: tuple[float, float, float, float]) -> list[BaseGeometry]:
    import httpx

    resp = httpx.post(config.OVERPASS_URL, data={"data": overpass_query(bbox)}, timeout=180)
    resp.raise_for_status()
    return parse_overpass(resp.json())


class WaterIndex:
    """Spatial index of water features in a city's UTM zone, for fast near-water checks."""

    def __init__(self, water_wgs84: list[BaseGeometry], epsg: int):
        self.epsg = epsg
        self.geoms = [to_metric(g, epsg) for g in water_wgs84]
        self.tree = STRtree(self.geoms) if self.geoms else None

    def near(self, site_wgs84: BaseGeometry, max_m: float = config.NEAR_WATER_M) -> bool:
        if self.tree is None:
            return False
        site = to_metric(site_wgs84, self.epsg)
        return any(self.geoms[int(i)].distance(site) <= max_m for i in self.tree.query(site.buffer(max_m)))
