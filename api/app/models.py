"""Pydantic request/response models (C-01)."""
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class Site(BaseModel):
    id: str
    city_id: str
    ward_id: Optional[str] = None
    area_m2: float = 0
    first_seen: Optional[date] = None
    last_seen: Optional[date] = None
    near_water: bool = False
    status: str = "active"
    fire_risk: int = 0
    centroid_lon: Optional[float] = None
    centroid_lat: Optional[float] = None


class ComplaintRequest(BaseModel):
    site_id: str
    language: str = "English"


class ComplaintEdit(BaseModel):
    draft_text: str


class Complaint(BaseModel):
    id: str
    site_id: str
    ward_id: Optional[str] = None
    draft_text: str
    language: str
    pdf_url: Optional[str] = None
    status: str = "draft"


class CitizenReport(BaseModel):
    lon: float
    lat: float
    note: Optional[str] = None
    photo_url: Optional[str] = None


# --- Member B's ingest payloads (section 6) ---------------------------------
# These are the contract between B's pipeline and this API. Field names match
# the Supabase schema. Extra keys B sends are rejected, so a mismatch shows up
# as a 422 naming the field rather than as silently-dropped data.
class DetectionIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    site_id: str
    scene_id: Optional[str] = None
    confidence: float = Field(ge=0, le=1)
    area_m2: float = Field(ge=0)
    thumb_url: Optional[str] = None
    detected_on: Optional[date] = None


class SiteIn(BaseModel):
    """A site B detected. `growth` is free text shown to officers."""
    model_config = ConfigDict(extra="forbid")

    id: str
    city_id: str
    centroid_lon: float
    centroid_lat: float
    area_m2: float = Field(default=0, ge=0)
    first_seen: Optional[date] = None
    last_seen: Optional[date] = None
    near_water: bool = False
    fire_risk: int = Field(default=0, ge=0, le=100)
    growth: Optional[str] = None
    status: Optional[str] = None


class FireEventIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    site_id: str
    detected_at: Optional[datetime] = None
    lat: Optional[float] = None
    lon: Optional[float] = None
    frp: Optional[float] = None
    confidence: Optional[float] = Field(default=None, ge=0, le=1)
    source: str = "VIIRS"


class IngestBatch(BaseModel):
    """What B posts to /ingest. Any subset of the three lists."""
    model_config = ConfigDict(extra="forbid")

    sites: list[SiteIn] = []
    detections: list[DetectionIn] = []
    fire_events: list[FireEventIn] = []
    run_id: Optional[str] = None


class PipelineRunRequest(BaseModel):
    """What C queues for B. `kind` and `params` match A's pipeline_runs table."""
    model_config = ConfigDict(extra="forbid")

    city_id: str
    kind: str = "detect"          # 'detect' | 'fires'
    start: Optional[date] = None  # B reads these as params.start / params.end
    end: Optional[date] = None


class ChatRequest(BaseModel):
    messages: Optional[list] = None   # [{role, content}] or use `message`
    message: Optional[str] = None
    city_id: Optional[str] = None
    language: str = "English"


class ChatResponse(BaseModel):
    answer: str
    tools_used: list
    site_ids: list


class ErrorBody(BaseModel):
    error: dict
