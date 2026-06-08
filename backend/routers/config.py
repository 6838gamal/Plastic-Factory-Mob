import os
from fastapi import APIRouter

router = APIRouter(prefix="/api", tags=["config"])

DEFAULT_API_URL = "https://plastic-factory-api.onrender.com"


@router.get("/config")
async def get_config():
    return {
        "base_url": os.getenv("API_BASE_URL", DEFAULT_API_URL),
    }
