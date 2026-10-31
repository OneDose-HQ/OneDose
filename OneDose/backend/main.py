# File: backend/main.py
# Owner: Bhavya  (only the owner edits this file)
# Purpose: Start the FastAPI app: enable CORS, register the route files (incl. the patient portal) and the auth router, add a health-check endpoint.
# Inputs: Settings from config.py.
# Outputs: A running API server.
# Depends on: config.py, auth.py, routes/*.py
#
# Run from the backend folder:  uvicorn main:app --reload --port 8000     (docs at http://localhost:8000/docs)
# The Vite dev server proxies /api to this port and strips the /api prefix, so routes here have no prefix.
import logging
from contextlib import asynccontextmanager

import psycopg
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

import auth
import db
from config import settings
from routes import analytics, patients, portal, prescriptions

log = logging.getLogger("onedose")


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.open_pool()
    yield
    db.close_pool()


app = FastAPI(title="OneDose API", version="1.0.0", lifespan=lifespan,
              description="Thin layer over the PostgreSQL safety engine. All safety decisions are made in SQL.")
app.add_middleware(CORSMiddleware, allow_origins=[settings.allowed_origin], allow_credentials=True,
                   allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"])

app.include_router(auth.router)
app.include_router(patients.router)
app.include_router(prescriptions.router)
app.include_router(analytics.router)
app.include_router(portal.router)
app.include_router(portal.staff_router)


@app.exception_handler(psycopg.Error)
async def database_error(request: Request, exc: psycopg.Error):
    http = db.error_to_http(exc)
    if http.status_code == 500:
        log.exception("database error on %s %s", request.method, request.url.path)
    return JSONResponse({"detail": http.detail}, status_code=http.status_code)


@app.get("/health", tags=["health"])
async def health():
    ok = await db.run(db.ping)
    return JSONResponse({"status": "ok" if ok else "database unreachable", "database": ok}, status_code=200 if ok else 503)
