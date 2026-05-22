"""Servicio core: validación de reglas de negocio y salud del clúster."""
import os
from fastapi import FastAPI
from fastapi.responses import PlainTextResponse
import httpx

API_URL = os.getenv("API_URL", "http://10.10.0.20:8080")

app = FastAPI(title="Reservas Core", version="1.0.0")


@app.get("/health")
def health():
    try:
        r = httpx.get(f"{API_URL}/health", timeout=3.0)
        api_ok = r.status_code == 200
    except Exception:
        api_ok = False
    return {"status": "ok" if api_ok else "degraded", "service": "reservas-core", "api_reachable": api_ok}


@app.get("/metrics", response_class=PlainTextResponse)
def metrics():
    ok = 0
    try:
        ok = 1 if httpx.get(f"{API_URL}/health", timeout=2.0).status_code == 200 else 0
    except Exception:
        ok = 0
    return f"# HELP lab_core_up Core activo\n# TYPE lab_core_up gauge\nlab_core_up {ok}\n"


@app.get("/")
def root():
    return {"service": "reservas-core", "role": "validación de negocio y enlace con API"}
