"""B-01: find Sentinel-2 L2A scenes for a city on Microsoft Planetary Computer."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

from . import config
from .config import City


@dataclass(frozen=True)
class SceneRef:
    stac_item_id: str
    acquired_at: datetime
    cloud_cover: float
    processing_baseline: float | None
    item: Any = None  # the signed pystac Item; None in tests


def scene_from_item(item: Any) -> SceneRef:
    props = item.properties
    baseline = props.get("s2:processing_baseline")
    return SceneRef(
        stac_item_id=item.id,
        acquired_at=datetime.fromisoformat(props["datetime"].replace("Z", "+00:00")),
        cloud_cover=float(props.get("eo:cloud_cover", 100.0)),
        processing_baseline=float(baseline) if baseline else None,
        item=item,
    )


def select_new_scenes(scenes: Iterable[SceneRef], existing_ids: set[str],
                      max_cloud: float = config.MAX_CLOUD_COVER) -> list[SceneRef]:
    """Keep scenes under the cloud limit that are not already in `scenes`, oldest first, no duplicates."""
    seen: set[str] = set(existing_ids)
    picked: list[SceneRef] = []
    for s in sorted(scenes, key=lambda s: s.acquired_at):
        if s.cloud_cover >= max_cloud or s.stac_item_id in seen:
            continue
        seen.add(s.stac_item_id)
        picked.append(s)
    return picked


def search_scenes(city: City, start: date, end: date,
                  max_cloud: float = config.MAX_CLOUD_COVER) -> list[SceneRef]:
    """Query the STAC API. Network call; items come back signed so their assets can be read."""
    import planetary_computer
    from pystac_client import Client

    catalog = Client.open(config.STAC_URL, modifier=planetary_computer.sign_inplace)
    search = catalog.search(
        collections=[config.COLLECTION],
        bbox=list(city.bbox),
        datetime=f"{start.isoformat()}/{end.isoformat()}",
        query={"eo:cloud_cover": {"lt": max_cloud}},
    )
    return [scene_from_item(item) for item in search.items()]
