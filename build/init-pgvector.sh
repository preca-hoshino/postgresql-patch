#!/bin/bash
# init-pgvector.sh — 自动为每个新创建的数据库启用 pgvector 扩展
# 该脚本被复制到 /docker-entrypoint-initdb.d/，在 PostgreSQL 初始化时自动执行

set -e

echo "[pgvector] Enabling vector extension for all databases..."

# 在默认数据库中启用 pgvector
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
    SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
EOSQL

echo "[pgvector] Extension 'vector' enabled successfully in database: $POSTGRES_DB"
