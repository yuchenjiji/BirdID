-- 在 Azure PostgreSQL Flexible Server 上执行此脚本完成建表
-- 连接后运行：psql -h YOUR_SERVER.postgres.database.azure.com -U YOUR_USER -d postgres -f init_db.sql

CREATE TABLE IF NOT EXISTS bird_history (
    id              TEXT PRIMARY KEY,
    uid             TEXT        NOT NULL,
    common_name     TEXT,
    scientific_name TEXT,
    score           FLOAT       NOT NULL DEFAULT 0.0,
    timestamp       TIMESTAMPTZ NOT NULL,
    description     TEXT,
    image_url       TEXT
);

CREATE INDEX IF NOT EXISTS idx_bird_history_uid_ts ON bird_history (uid, timestamp DESC);
