"""Drishti geospatial AI pipeline (Member B).

Turns Sentinel-2 imagery into dumpsite records in Supabase:
search scenes -> mask clouds -> 6-band stack -> tiles -> Prithvi -> polygons -> sites,
plus the fire layer (NASA FIRMS + Open-Meteo -> fire events and fire-risk scores).
"""

__version__ = "0.1.0"
