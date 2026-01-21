"""
FastAPI YouTube Backend for AI Trainer
Serves workout videos from curated YouTube playlists
"""

import os
import time
from typing import Dict, List, Optional

import json
import urllib.parse
import urllib.request

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from googleapiclient.discovery import build

# Configuration
_ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path=_ENV_PATH)
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY", "")
PLACES_API_KEY = os.getenv("GOOGLE_PLACES_API_KEY", "")
if not YOUTUBE_API_KEY:
    raise RuntimeError("Missing YOUTUBE_API_KEY env var")

# Search queries for each category (embeddable videos only)
CATEGORY_QUERIES = {
    "all": "full body workout",
    "cardio": "cardio workout",
    "strength": "strength training workout",
    "yoga": "yoga flow",
    "hiit": "HIIT workout",
}

# Fallback video IDs if search fails
CATEGORY_VIDEOS = {
    "all": [
        "MLpne8lFxHs",  # 10 MIN MORNING YOGA FLOW - Yoga with Adriene
        "IODxDxX7oi4",  # 20 MIN FULL BODY WORKOUT - MadFit
        "v7AYKMP6rOE",  # Morning Yoga For Beginners - Yoga with Adriene
        "9jcKUb_-1eA",  # 12 MIN AB WORKOUT - Chloe Ting
        "6K8_N4XtTOQ",  # 15 MIN FULL BODY WORKOUT - FitnessBlender
    ],
    "cardio": [
        "MLpne8lFxHs",
        "6K8_N4XtTOQ",
        "9jcKUb_-1eA",
    ],
    "strength": [
        "IODxDxX7oi4",
        "6K8_N4XtTOQ",
    ],
    "yoga": [
        "MLpne8lFxHs",
        "v7AYKMP6rOE",
    ],
    "hiit": [
        "9jcKUb_-1eA",
        "IODxDxX7oi4",
    ],
}

app = FastAPI(title="AI Trainer YouTube API", version="1.0.0")

# Allow CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)

# Simple in-memory cache
_CACHE: Dict[str, Dict] = {}
CACHE_TTL_SECONDS = 300  # 5 minutes


def _cache_get(key: str) -> Optional[Dict]:
    item = _CACHE.get(key)
    if not item:
        return None
    if time.time() - item["ts"] > CACHE_TTL_SECONDS:
        _CACHE.pop(key, None)
        return None
    return item["value"]


def _cache_set(key: str, value: Dict) -> None:
    _CACHE[key] = {"ts": time.time(), "value": value}


def _parse_iso8601_duration(duration: str) -> int:
    """Convert YouTube ISO 8601 duration (PT15M30S) to seconds"""
    if not duration or not duration.startswith("PT"):
        return 0

    dur = duration[2:]
    num = ""
    hours = minutes = seconds = 0

    for ch in dur:
        if ch.isdigit():
            num += ch
            continue
        if ch == "H":
            hours = int(num or "0")
        elif ch == "M":
            minutes = int(num or "0")
        elif ch == "S":
            seconds = int(num or "0")
        num = ""

    return hours * 3600 + minutes * 60 + seconds


def _format_duration(total_seconds: int) -> str:
    """Format seconds as human readable duration"""
    if total_seconds >= 3600:
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        return f"{hours}h {minutes}m"
    elif total_seconds >= 60:
        minutes = total_seconds // 60
        return f"{minutes} min"
    else:
        return f"{total_seconds}s"


def _determine_difficulty(title: str, duration_seconds: int) -> str:
    """Determine workout difficulty based on title and duration"""
    title_lower = title.lower()

    if any(word in title_lower for word in ["beginner", "easy", "gentle", "starter"]):
        return "beginner"
    elif any(word in title_lower for word in ["advanced", "intense", "extreme", "hardcore"]):
        return "advanced"
    elif duration_seconds > 2400:  # > 40 minutes
        return "advanced"
    elif duration_seconds < 600:   # < 10 minutes
        return "beginner"
    else:
        return "intermediate"


def fetch_videos_by_ids(video_ids: List[str]) -> List[Dict]:
    """Fetch videos by their YouTube IDs"""
    try:
        if not video_ids:
            return []

        # Get video details
        videos_request = youtube.videos().list(
            part="snippet,contentDetails,statistics,status",
            id=",".join(video_ids)
        )
        videos_response = videos_request.execute()

        videos = []
        for item in videos_response.get("items", []):
            status = item.get("status", {})
            if not status.get("embeddable", False):
                continue
            if status.get("privacyStatus") != "public":
                continue

            snippet = item["snippet"]
            content_details = item["contentDetails"]
            statistics = item.get("statistics", {})

            duration_seconds = _parse_iso8601_duration(content_details.get("duration", ""))

            video_data = {
                "id": item["id"],
                "title": snippet["title"],
                "instructor": snippet["channelTitle"],
                "duration": duration_seconds // 60,  # Convert to minutes
                "formattedDuration": _format_duration(duration_seconds),
                "difficulty": _determine_difficulty(snippet["title"], duration_seconds),
                "thumbnailURL": snippet["thumbnails"]["high"]["url"],
                "viewCount": int(statistics.get("viewCount", 0)),
                "description": snippet.get("description", ""),
                "embedURL": f"https://www.youtube-nocookie.com/embed/{item['id']}",
                "youtubeURL": f"https://www.youtube.com/watch?v={item['id']}"
            }
            videos.append(video_data)

        return videos

    except Exception as e:
        print(f"Error fetching videos {video_ids}: {e}")
        return []


def _search_video_ids(query: str, limit: int, duration: Optional[str]) -> List[str]:
    """Search YouTube for embeddable video IDs"""
    try:
        params = {
            "part": "id",
            "q": query,
            "type": "video",
            "maxResults": limit,
            "videoEmbeddable": "true",
            "safeSearch": "moderate",
        }
        if duration:
            params["videoDuration"] = duration

        search_request = youtube.search().list(**params)
        search_response = search_request.execute()

        return [
            item["id"]["videoId"]
            for item in search_response.get("items", [])
            if item.get("id", {}).get("videoId")
        ]
    except Exception as e:
        print(f"Error searching videos for '{query}': {e}")
        return []


def fetch_videos_by_search(query: str, limit: int) -> List[Dict]:
    """Search YouTube for embeddable videos and return detailed results"""
    video_ids: List[str] = []
    for duration in ("medium", "long"):
        if len(video_ids) >= limit:
            break
        for video_id in _search_video_ids(query, limit - len(video_ids), duration):
            if video_id not in video_ids:
                video_ids.append(video_id)

    videos = fetch_videos_by_ids(video_ids)
    # Filter out very short clips (often Shorts) which are prone to embed errors
    return [video for video in videos if video.get("duration", 0) >= 1]


def _places_request(path: str, params: Dict[str, str]) -> Dict:
    if not PLACES_API_KEY:
        return {"status": "REQUEST_DENIED", "error_message": "Missing GOOGLE_PLACES_API_KEY"}

    params_with_key = {**params, "key": PLACES_API_KEY}
    query = urllib.parse.urlencode(params_with_key)
    url = f"https://maps.googleapis.com/maps/api/place/{path}/json?{query}"
    request = urllib.request.Request(url, headers={"User-Agent": "ai-trainer-backend"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read()
        return json.loads(data.decode("utf-8"))
    except Exception as e:
        return {"status": "UNKNOWN_ERROR", "error_message": str(e)}


@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "ai-trainer-youtube-api"}


@app.get("/categories")
def get_categories():
    """Get available workout categories"""
    return {
        "categories": [
            {"key": "all", "name": "All Workouts", "emoji": "🏃‍♂️"},
            {"key": "cardio", "name": "Cardio", "emoji": "❤️"},
            {"key": "strength", "name": "Strength", "emoji": "💪"},
            {"key": "yoga", "name": "Yoga", "emoji": "🧘‍♀️"},
            {"key": "hiit", "name": "HIIT", "emoji": "⚡"},
        ]
    }


@app.get("/videos")
def get_videos(
    category: str = Query("all", description="Workout category"),
    limit: int = Query(20, ge=1, le=50, description="Max videos to return")
):
    """Get workout videos for a category"""

    # Normalize category
    category = category.lower()
    if category not in CATEGORY_VIDEOS:
        raise HTTPException(status_code=400, detail=f"Invalid category: {category}")

    cache_key = f"videos:{category}:{limit}"
    cached = _cache_get(cache_key)
    if cached:
        return cached

    videos = []
    query = CATEGORY_QUERIES.get(category)
    if query:
        videos = fetch_videos_by_search(query, limit)

    if not videos:
        video_ids = CATEGORY_VIDEOS[category][:limit]  # Limit the video IDs
        videos = fetch_videos_by_ids(video_ids)

    result = {
        "category": category,
        "total": len(videos),
        "videos": videos
    }

    _cache_set(cache_key, result)
    return result


@app.get("/video/{video_id}")
def get_video_details(video_id: str):
    """Get detailed information for a specific video"""
    try:
        videos_request = youtube.videos().list(
            part="snippet,contentDetails,statistics",
            id=video_id
        )
        response = videos_request.execute()

        if not response.get("items"):
            raise HTTPException(status_code=404, detail="Video not found")

        item = response["items"][0]
        snippet = item["snippet"]
        content_details = item["contentDetails"]
        statistics = item.get("statistics", {})

        duration_seconds = _parse_iso8601_duration(content_details.get("duration", ""))

        return {
            "id": video_id,
            "title": snippet["title"],
            "instructor": snippet["channelTitle"],
            "duration": duration_seconds // 60,
            "formattedDuration": _format_duration(duration_seconds),
            "difficulty": _determine_difficulty(snippet["title"], duration_seconds),
            "thumbnailURL": snippet["thumbnails"]["high"]["url"],
            "viewCount": int(statistics.get("viewCount", 0)),
            "likeCount": int(statistics.get("likeCount", 0)),
            "description": snippet.get("description", ""),
            "embedURL": f"https://www.youtube-nocookie.com/embed/{video_id}",
            "youtubeURL": f"https://www.youtube.com/watch?v={video_id}",
            "publishedAt": snippet.get("publishedAt")
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching video: {e}")


@app.get("/gyms/nearby")
def get_nearby_gyms(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
    radius: int = Query(5000, ge=100, le=50000, description="Search radius in meters"),
    keyword: Optional[str] = Query(None, description="Optional keyword filter"),
):
    """Proxy to Google Places Nearby Search for gyms."""
    params: Dict[str, str] = {
        "location": f"{lat},{lng}",
        "radius": str(radius),
        "type": "gym",
    }
    if keyword:
        params["keyword"] = keyword
    return _places_request("nearbysearch", params)


@app.get("/gyms/search")
def search_gyms(
    query: str = Query(..., description="Search text"),
    lat: Optional[float] = Query(None, description="Optional latitude"),
    lng: Optional[float] = Query(None, description="Optional longitude"),
):
    """Proxy to Google Places Text Search for gyms."""
    trimmed = query.strip()
    if not trimmed:
        raise HTTPException(status_code=400, detail="Query must not be empty")

    params: Dict[str, str] = {"query": f"gym near {trimmed}"}
    if lat is not None and lng is not None:
        params["location"] = f"{lat},{lng}"
        params["radius"] = "10000"
    return _places_request("textsearch", params)


@app.get("/gyms/photo")
def get_gym_photo(
    ref: str = Query(..., description="Google Places photo reference"),
    maxwidth: int = Query(400, ge=100, le=1600, description="Photo max width"),
):
    """Proxy Google Places photo to avoid exposing API key to clients."""
    if not PLACES_API_KEY:
        raise HTTPException(status_code=500, detail="Missing GOOGLE_PLACES_API_KEY")

    params = urllib.parse.urlencode(
        {"maxwidth": str(maxwidth), "photoreference": ref, "key": PLACES_API_KEY}
    )
    url = f"https://maps.googleapis.com/maps/api/place/photo?{params}"
    request = urllib.request.Request(url, headers={"User-Agent": "ai-trainer-backend"})

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read()
            content_type = response.headers.get("Content-Type", "image/jpeg")
        return Response(content=data, media_type=content_type)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Photo fetch failed: {e}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)