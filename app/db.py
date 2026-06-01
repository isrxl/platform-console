"""SQL data access via pyodbc.

The ODBC connection string is fetched from Key Vault (secret db-connection-string)
at first use and cached. The DB is reached over a private endpoint. A local
override (DB_CONNECTION_STRING) is supported for development.
"""
import functools

import pyodbc

import keyvault
from config import Config

DEFAULT_FLAGS = [
    ("new_dashboard_ui", 0),
    ("export_to_csv", 1),
    ("dark_mode", 0),
    ("beta_reporting_engine", 0),
    ("maintenance_mode", 0),
]


@functools.lru_cache(maxsize=1)
def _connection_string():
    if Config.DB_CONNECTION_STRING:
        return Config.DB_CONNECTION_STRING
    return keyvault.get_secret(Config.DB_SECRET_NAME)


_schema_initialized = False


def _open_connection():
    """Open a DB connection without triggering schema init."""
    return pyodbc.connect(_connection_string(), timeout=15)


def _ensure_schema():
    """Create tables and seed default flags on first use (idempotent)."""
    global _schema_initialized
    if _schema_initialized:
        return
    init_schema()
    _schema_initialized = True


def get_connection():
    _ensure_schema()
    return _open_connection()


def healthcheck():
    """Return True if SELECT 1 succeeds, else raise."""
    with get_connection() as conn:
        conn.cursor().execute("SELECT 1").fetchone()
    return True


def init_schema():
    """Idempotently create tables and seed default flags for this environment."""
    with _open_connection() as conn:
        cur = conn.cursor()
        cur.execute(SCHEMA_SQL)
        for flag_name, default in DEFAULT_FLAGS:
            cur.execute(
                """
                IF NOT EXISTS (
                    SELECT 1 FROM feature_flags
                    WHERE flag_name = ? AND environment = ?
                )
                INSERT INTO feature_flags (flag_name, environment, is_enabled)
                VALUES (?, ?, ?)
                """,
                flag_name,
                Config.ENVIRONMENT,
                flag_name,
                Config.ENVIRONMENT,
                default,
            )
        conn.commit()


def get_flags():
    with get_connection() as conn:
        rows = conn.cursor().execute(
            """
            SELECT id, flag_name, environment, is_enabled, updated_at, updated_by
            FROM feature_flags WHERE environment = ? ORDER BY flag_name
            """,
            Config.ENVIRONMENT,
        ).fetchall()
    return [
        {
            "id": r[0],
            "flag_name": r[1],
            "environment": r[2],
            "is_enabled": bool(r[3]),
            "updated_at": r[4].isoformat() if r[4] else None,
            "updated_by": r[5],
        }
        for r in rows
    ]


def set_flag(flag_id, is_enabled, updated_by="ui-user"):
    with get_connection() as conn:
        conn.cursor().execute(
            """
            UPDATE feature_flags
            SET is_enabled = ?, updated_at = SYSUTCDATETIME(), updated_by = ?
            WHERE id = ?
            """,
            1 if is_enabled else 0,
            updated_by,
            flag_id,
        )
        conn.commit()


def get_deployments(limit=50):
    with get_connection() as conn:
        rows = conn.cursor().execute(
            """
            SELECT TOP (?) id, environment, version, semantic_version,
                   deployed_at, deployed_by, status
            FROM deployments ORDER BY deployed_at DESC
            """,
            limit,
        ).fetchall()
    return [
        {
            "id": r[0],
            "environment": r[1],
            "version": r[2],
            "semantic_version": r[3],
            "deployed_at": r[4].isoformat() if r[4] else None,
            "deployed_by": r[5],
            "status": r[6],
        }
        for r in rows
    ]


def add_deployment(environment, version, semantic_version, deployed_by, status="success"):
    with get_connection() as conn:
        conn.cursor().execute(
            """
            INSERT INTO deployments
                (environment, version, semantic_version, deployed_by, status)
            VALUES (?, ?, ?, ?, ?)
            """,
            environment,
            version,
            semantic_version,
            deployed_by,
            status,
        )
        conn.commit()


def get_releases():
    with get_connection() as conn:
        cur = conn.cursor()
        notes = cur.execute(
            """
            SELECT id, version, semantic_version, content, published_at, published_by
            FROM release_notes ORDER BY published_at DESC
            """
        ).fetchall()
        items = cur.execute(
            """
            SELECT id, release_note_id, item_type, description, sort_order
            FROM release_note_items ORDER BY sort_order
            """
        ).fetchall()

    items_by_note = {}
    for it in items:
        items_by_note.setdefault(it[1], []).append(
            {"id": it[0], "item_type": it[2], "description": it[3], "sort_order": it[4]}
        )

    return [
        {
            "id": n[0],
            "version": n[1],
            "semantic_version": n[2],
            "content": n[3],
            "published_at": n[4].isoformat() if n[4] else None,
            "published_by": n[5],
            "items": items_by_note.get(n[0], []),
        }
        for n in notes
    ]


def add_release(version, semantic_version, content, published_by, items):
    with get_connection() as conn:
        cur = conn.cursor()
        note_id = cur.execute(
            """
            INSERT INTO release_notes (version, semantic_version, content, published_by)
            OUTPUT INSERTED.id
            VALUES (?, ?, ?, ?)
            """,
            version,
            semantic_version,
            content,
            published_by,
        ).fetchone()[0]

        for idx, item in enumerate(items or []):
            cur.execute(
                """
                INSERT INTO release_note_items
                    (release_note_id, item_type, description, sort_order)
                VALUES (?, ?, ?, ?)
                """,
                note_id,
                item.get("item_type", "note"),
                item.get("description", ""),
                idx,
            )
        conn.commit()
    return note_id


SCHEMA_SQL = """
IF OBJECT_ID('dbo.feature_flags', 'U') IS NULL
CREATE TABLE feature_flags (
    id           INT IDENTITY PRIMARY KEY,
    flag_name    NVARCHAR(100) NOT NULL,
    environment  NVARCHAR(20)  NOT NULL,
    is_enabled   BIT           NOT NULL DEFAULT 0,
    updated_at   DATETIME2     DEFAULT SYSUTCDATETIME(),
    updated_by   NVARCHAR(100) DEFAULT 'system'
);

IF OBJECT_ID('dbo.deployments', 'U') IS NULL
CREATE TABLE deployments (
    id               INT IDENTITY PRIMARY KEY,
    environment      NVARCHAR(20)  NOT NULL,
    version          NVARCHAR(100) NOT NULL,
    semantic_version NVARCHAR(20)  NULL,
    deployed_at      DATETIME2     DEFAULT SYSUTCDATETIME(),
    deployed_by      NVARCHAR(100) DEFAULT 'pipeline',
    status           NVARCHAR(20)  DEFAULT 'success'
);

IF OBJECT_ID('dbo.release_notes', 'U') IS NULL
CREATE TABLE release_notes (
    id               INT IDENTITY PRIMARY KEY,
    version          NVARCHAR(100) NOT NULL,
    semantic_version NVARCHAR(20)  NOT NULL,
    content          NVARCHAR(MAX) NOT NULL,
    published_at     DATETIME2     DEFAULT SYSUTCDATETIME(),
    published_by     NVARCHAR(100) NOT NULL
);

IF OBJECT_ID('dbo.release_note_items', 'U') IS NULL
CREATE TABLE release_note_items (
    id              INT IDENTITY PRIMARY KEY,
    release_note_id INT FOREIGN KEY REFERENCES release_notes(id),
    item_type       NVARCHAR(20)  NOT NULL,
    description     NVARCHAR(500) NOT NULL,
    sort_order      INT           DEFAULT 0
);
"""
