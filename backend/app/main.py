from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

from app.api.v1.router import router as api_v1_router
from app.core.config import settings
from app.middleware.security import add_security_headers

app = FastAPI(title="API", docs_url=None if settings.ENV == "production" else "/docs")

# Security headers — added first, runs after CORS
app.add_middleware(BaseHTTPMiddleware, dispatch=add_security_headers)

# CORS — added last, runs first (outermost) so preflight OPTIONS are handled before any other middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["Authorization", "Content-Type", "Accept", "Origin", "X-Requested-With"],
)

app.include_router(api_v1_router, prefix="/api/v1")


@app.get("/health")
def health():
    return {"status": "ok"}
