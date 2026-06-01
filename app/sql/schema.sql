-- Platform Console schema (handoff Section 6.4).
-- Idempotent: safe to run repeatedly. The app also applies this on first use
-- via db.init_schema(), but it is provided here for manual bootstrap.

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
    version          NVARCHAR(100) NOT NULL,  -- Git SHA
    semantic_version NVARCHAR(20)  NULL,       -- e.g. v1.2.0
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
    item_type       NVARCHAR(20)  NOT NULL,  -- feature / fix / note / breaking
    description     NVARCHAR(500) NOT NULL,
    sort_order      INT           DEFAULT 0
);
