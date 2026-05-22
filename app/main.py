"""
API de reservas académicas — autenticación, CRUD recursos/reservas, auditoría.
"""
from __future__ import annotations

import json
import logging
import os
import secrets
import traceback
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any, Optional

import psycopg2
import psycopg2.extras
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, PlainTextResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

DB_HOST = os.getenv("DB_HOST", "10.10.0.40")
DB_NAME = os.getenv("DB_NAME", "reservas")
DB_USER = os.getenv("DB_USER", "lab")
DB_PASS = os.getenv("DB_PASS", "lab_secret_change_me")

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("reservas-api")
security = HTTPBearer(auto_error=False)
_active_tokens: dict[str, int] = {}


def db_conn():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


def log_event(
    level: str,
    source: str,
    message: str,
    context: Optional[dict] = None,
    *,
    user_id: Optional[int] = None,
):
    payload = dict(context or {})
    if user_id is not None:
        payload["user_id"] = user_id
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO event_logs (level, source, message, context) VALUES (%s,%s,%s,%s)",
                    (level, source, message, json.dumps(payload) if payload else None),
                )
            conn.commit()
    except Exception as exc:
        log.error("No se pudo registrar evento: %s", exc)


class LoginIn(BaseModel):
    email: str
    password: str


class ResourceIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    resource_type: str = Field(default="laboratorio", max_length=60)
    capacity: int = Field(default=1, ge=1)
    available: bool = True
    description: Optional[str] = None


class ResourceUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    resource_type: Optional[str] = Field(default=None, max_length=60)
    capacity: Optional[int] = Field(default=None, ge=1)
    available: Optional[bool] = None
    description: Optional[str] = None


class ReservationIn(BaseModel):
    resource_id: int
    starts_at: datetime
    ends_at: datetime
    notes: Optional[str] = None
    status: str = Field(default="confirmed", max_length=30)


class ReservationUpdate(BaseModel):
    starts_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    status: Optional[str] = Field(default=None, max_length=30)
    notes: Optional[str] = None


def verify_password(plain: str, stored: str) -> bool:
    if stored.startswith("plain:"):
        return plain == stored[6:]
    return plain == "lab123" and stored.endswith("placeholder")


def auth_user(creds: Optional[HTTPAuthorizationCredentials] = Depends(security)) -> int:
    if not creds or creds.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Token requerido")
    uid = _active_tokens.get(creds.credentials)
    if not uid:
        log_event("warning", "auth", "Token inválido o expirado", {})
        raise HTTPException(status_code=401, detail="Token inválido")
    return uid


def _check_overlap(
    cur,
    resource_id: int,
    starts_at: datetime,
    ends_at: datetime,
    exclude_id: Optional[int] = None,
):
    q = """
        SELECT id FROM reservations
        WHERE resource_id = %s AND status != 'cancelled'
          AND starts_at < %s AND ends_at > %s
    """
    params: list[Any] = [resource_id, ends_at, starts_at]
    if exclude_id is not None:
        q += " AND id != %s"
        params.append(exclude_id)
    cur.execute(q, params)
    if cur.fetchone():
        raise HTTPException(409, detail="El recurso ya tiene una reserva en ese horario")


@asynccontextmanager
async def lifespan(_: FastAPI):
    log_event("info", "api", "API de reservas iniciada", {"host": DB_HOST})
    yield
    log_event("info", "api", "API de reservas detenida", {})


app = FastAPI(
    title="Reservas Lab Académico",
    version="1.1.0",
    description="Autenticación, CRUD de recursos y reservas, registro de eventos/errores.",
    lifespan=lifespan,
)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    level = "warning" if exc.status_code < 500 else "error"
    log_event(
        level,
        "http",
        exc.detail if isinstance(exc.detail, str) else str(exc.detail),
        {"path": request.url.path, "method": request.method, "status": exc.status_code},
    )
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    log_event(
        "warning",
        "validation",
        "Petición inválida",
        {"path": request.url.path, "errors": exc.errors()},
    )
    return JSONResponse(status_code=422, content={"detail": exc.errors()})


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    log_event(
        "error",
        "api",
        str(exc),
        {
            "path": request.url.path,
            "method": request.method,
            "traceback": traceback.format_exc(),
        },
    )
    log.exception("Error no controlado en %s", request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Error interno del servidor"})


@app.middleware("http")
async def log_requests(request: Request, call_next):
    try:
        response = await call_next(request)
        if response.status_code >= 400:
            log_event(
                "warning" if response.status_code < 500 else "error",
                "http",
                f"{request.method} {request.url.path} -> {response.status_code}",
                {"status": response.status_code},
            )
        return response
    except Exception:
        raise


# --- Autenticación básica ---


@app.post("/auth/login", tags=["auth"])
def login(body: LoginIn):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, email, full_name, password_hash FROM users WHERE email = %s",
                (body.email,),
            )
            row = cur.fetchone()
    if not row or not verify_password(body.password, row["password_hash"]):
        log_event("warning", "auth", "Login fallido", {"email": body.email})
        raise HTTPException(401, detail="Credenciales inválidas")
    token = secrets.token_urlsafe(32)
    _active_tokens[token] = row["id"]
    log_event("info", "auth", "Login exitoso", {"email": row["email"]}, user_id=row["id"])
    return {
        "access_token": token,
        "token_type": "bearer",
        "user_id": row["id"],
        "email": row["email"],
        "full_name": row["full_name"],
    }


@app.post("/auth/logout", tags=["auth"])
def logout(uid: int = Depends(auth_user), creds: HTTPAuthorizationCredentials = Depends(security)):
    if creds and creds.credentials in _active_tokens:
        del _active_tokens[creds.credentials]
    log_event("info", "auth", "Logout", {}, user_id=uid)
    return {"ok": True}


@app.get("/auth/me", tags=["auth"])
def me(uid: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, email, full_name, created_at FROM users WHERE id = %s", (uid,))
            row = cur.fetchone()
    if not row:
        raise HTTPException(404, detail="Usuario no encontrado")
    return row


# --- Salud y métricas ---


@app.get("/health", tags=["sistema"])
def health():
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return {"status": "ok", "service": "reservas-api", "db": "up"}
    except Exception as exc:
        log_event("error", "health", str(exc))
        raise HTTPException(503, detail="Base de datos no disponible") from exc


@app.get("/metrics", response_class=PlainTextResponse, tags=["sistema"])
def metrics():
    try:
        with db_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS c FROM reservations")
                res = cur.fetchone()["c"]
                cur.execute("SELECT COUNT(*) AS c FROM resources WHERE available")
                avail = cur.fetchone()["c"]
    except Exception:
        res, avail = 0, 0
    return (
        "# HELP lab_reservations_total Reservas registradas\n"
        "# TYPE lab_reservations_total gauge\n"
        f"lab_reservations_total {res}\n"
        "# HELP lab_resources_available Recursos disponibles\n"
        "# TYPE lab_resources_available gauge\n"
        f"lab_resources_available {avail}\n"
        "# HELP lab_up API activa\n"
        "# TYPE lab_up gauge\n"
        "lab_up 1\n"
    )


# --- CRUD recursos académicos ---


@app.get("/resources", tags=["recursos"])
def list_resources(_: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM resources ORDER BY id")
            rows = cur.fetchall()
    return {"items": rows}


@app.post("/resources", status_code=201, tags=["recursos"])
def create_resource(body: ResourceIn, uid: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO resources (name, resource_type, capacity, available, description)
                   VALUES (%s,%s,%s,%s,%s) RETURNING *""",
                (body.name, body.resource_type, body.capacity, body.available, body.description),
            )
            row = cur.fetchone()
        conn.commit()
    log_event("info", "resources", "Recurso creado", {"id": row["id"]}, user_id=uid)
    return row


@app.get("/resources/{resource_id}", tags=["recursos"])
def get_resource(resource_id: int, _: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM resources WHERE id = %s", (resource_id,))
            row = cur.fetchone()
    if not row:
        raise HTTPException(404, detail="Recurso no encontrado")
    return row


@app.put("/resources/{resource_id}", tags=["recursos"])
def update_resource(resource_id: int, body: ResourceUpdate, uid: int = Depends(auth_user)):
    fields = {k: v for k, v in body.model_dump().items() if v is not None}
    if not fields:
        raise HTTPException(400, detail="Sin campos para actualizar")
    sets = ", ".join(f"{k} = %s" for k in fields)
    vals = list(fields.values()) + [resource_id]
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE resources SET {sets} WHERE id = %s RETURNING *", vals)
            row = cur.fetchone()
        conn.commit()
    if not row:
        raise HTTPException(404, detail="Recurso no encontrado")
    log_event("info", "resources", "Recurso actualizado", {"id": resource_id}, user_id=uid)
    return row


@app.delete("/resources/{resource_id}", status_code=204, tags=["recursos"])
def delete_resource(resource_id: int, uid: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS c FROM reservations WHERE resource_id = %s", (resource_id,))
            if cur.fetchone()["c"] > 0:
                log_event(
                    "warning",
                    "resources",
                    "No se puede eliminar: tiene reservas",
                    {"id": resource_id},
                    user_id=uid,
                )
                raise HTTPException(409, detail="El recurso tiene reservas asociadas")
            cur.execute("DELETE FROM resources WHERE id = %s RETURNING id", (resource_id,))
            row = cur.fetchone()
        conn.commit()
    if not row:
        raise HTTPException(404, detail="Recurso no encontrado")
    log_event("info", "resources", "Recurso eliminado", {"id": resource_id}, user_id=uid)


# --- CRUD reservas ---


@app.get("/reservations", tags=["reservas"])
def list_reservations(
    resource_id: Optional[int] = None,
    status: Optional[str] = None,
    _: int = Depends(auth_user),
):
    clauses = []
    params: list[Any] = []
    if resource_id is not None:
        clauses.append("r.resource_id = %s")
        params.append(resource_id)
    if status:
        clauses.append("r.status = %s")
        params.append(status)
    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"""SELECT r.*, u.email AS user_email, res.name AS resource_name
                    FROM reservations r
                    JOIN users u ON u.id = r.user_id
                    JOIN resources res ON res.id = r.resource_id
                    {where}
                    ORDER BY r.starts_at DESC""",
                params,
            )
            rows = cur.fetchall()
    return {"items": rows}


@app.post("/reservations", status_code=201, tags=["reservas"])
def create_reservation(body: ReservationIn, uid: int = Depends(auth_user)):
    if body.ends_at <= body.starts_at:
        raise HTTPException(400, detail="ends_at debe ser posterior a starts_at")
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT available FROM resources WHERE id = %s", (body.resource_id,))
            res = cur.fetchone()
            if not res:
                raise HTTPException(404, detail="Recurso no encontrado")
            if not res["available"]:
                raise HTTPException(409, detail="Recurso no disponible")
            _check_overlap(cur, body.resource_id, body.starts_at, body.ends_at)
            cur.execute(
                """INSERT INTO reservations (user_id, resource_id, starts_at, ends_at, status, notes)
                   VALUES (%s,%s,%s,%s,%s,%s) RETURNING *""",
                (uid, body.resource_id, body.starts_at, body.ends_at, body.status, body.notes),
            )
            row = cur.fetchone()
        conn.commit()
    log_event("info", "reservations", "Reserva creada", {"id": row["id"]}, user_id=uid)
    return row


@app.get("/reservations/{res_id}", tags=["reservas"])
def get_reservation(res_id: int, _: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT r.*, u.email AS user_email, res.name AS resource_name
                   FROM reservations r
                   JOIN users u ON u.id = r.user_id
                   JOIN resources res ON res.id = r.resource_id
                   WHERE r.id = %s""",
                (res_id,),
            )
            row = cur.fetchone()
    if not row:
        raise HTTPException(404, detail="Reserva no encontrada")
    return row


@app.put("/reservations/{res_id}", tags=["reservas"])
def update_reservation(res_id: int, body: ReservationUpdate, uid: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM reservations WHERE id = %s", (res_id,))
            current = cur.fetchone()
            if not current:
                raise HTTPException(404, detail="Reserva no encontrada")
            starts = body.starts_at or current["starts_at"]
            ends = body.ends_at or current["ends_at"]
            if ends <= starts:
                raise HTTPException(400, detail="ends_at debe ser posterior a starts_at")
            resource_id = current["resource_id"]
            if body.starts_at or body.ends_at:
                _check_overlap(cur, resource_id, starts, ends, exclude_id=res_id)
            fields = {k: v for k, v in body.model_dump().items() if v is not None}
            if not fields:
                raise HTTPException(400, detail="Sin campos para actualizar")
            sets = ", ".join(f"{k} = %s" for k in fields)
            vals = list(fields.values()) + [res_id]
            cur.execute(f"UPDATE reservations SET {sets} WHERE id = %s RETURNING *", vals)
            row = cur.fetchone()
        conn.commit()
    log_event("info", "reservations", "Reserva actualizada", {"id": res_id}, user_id=uid)
    return row


@app.delete("/reservations/{res_id}", status_code=204, tags=["reservas"])
def delete_reservation(res_id: int, uid: int = Depends(auth_user)):
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM reservations WHERE id = %s RETURNING id", (res_id,))
            row = cur.fetchone()
        conn.commit()
    if not row:
        raise HTTPException(404, detail="Reserva no encontrada")
    log_event("info", "reservations", "Reserva eliminada", {"id": res_id}, user_id=uid)


# --- Eventos y errores ---


def _fetch_events(limit: int = 50, level: Optional[str] = None, source: Optional[str] = None):
    q = "SELECT * FROM event_logs WHERE 1=1"
    params: list[Any] = []
    if level:
        q += " AND level = %s"
        params.append(level)
    if source:
        q += " AND source = %s"
        params.append(source)
    q += " ORDER BY id DESC LIMIT %s"
    params.append(min(max(limit, 1), 200))
    with db_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(q, params)
            return cur.fetchall()


@app.get("/events", tags=["eventos"])
def list_events(
    limit: int = 50,
    level: Optional[str] = None,
    source: Optional[str] = None,
    _: int = Depends(auth_user),
):
    return {"items": _fetch_events(limit=limit, level=level, source=source)}


@app.get("/events/errors", tags=["eventos"])
def list_errors(limit: int = 50, _: int = Depends(auth_user)):
    return {"items": _fetch_events(limit=limit, level="error")}
