"""Ward mapping (C-05, C-06): assign each site to the ward holding its centroid."""
from ..repo import get_repo


def assign_site_to_ward(site) -> dict:
    """Return {'ward_id', 'officer_email'} for a single site, or {} if none."""
    repo = get_repo()
    pt = site.get("centroid")
    if pt is None:
        return {}
    ward = repo.ward_containing(pt, city_id=site.get("city_id"))
    if not ward:
        return {}
    return {"ward_id": ward["id"], "officer_email": ward["officer_email"]}


def assign_all(city_id=None) -> int:
    """Assign every unassigned site to a ward. Returns how many were assigned."""
    repo = get_repo()
    n = 0
    for s in repo.list_sites(city_id=city_id):
        res = assign_site_to_ward(s)
        if res:
            repo.update_site(s["id"], ward_id=res["ward_id"])
            n += 1
    return n
