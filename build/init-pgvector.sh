#!/bin/bash
# init-extensions.sh — 自动为每个新创建的数据库启用内置扩展和 pgvector
# 该脚本被复制到 /docker-entrypoint-initdb.d/，在 PostgreSQL 初始化时自动执行
#
# 启用的扩展:
#   pgvector          — 向量相似度搜索 (需编译安装)
#   pg_stat_statements— SQL 执行统计 (内核自带，需 shared_preload_libraries)
#   pg_trgm           — 模糊文本搜索 (内核自带)
#   pgcrypto          — 加密函数 (内核自带)
#   hstore            — 键值对存储 (内核自带)

set -e

DB_NAME="${POSTGRES_DB:-postgres}"

echo "[extensions] Enabling extensions in database: $DB_NAME"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
    -- pgvector: 向量相似度搜索
    CREATE EXTENSION IF NOT EXISTS vector;

    -- pg_stat_statements: SQL 执行统计
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

    -- pg_trgm: 模糊文本搜索 (支持 LIKE/ILIKE 加速和相似度匹配)
    CREATE EXTENSION IF NOT EXISTS pg_trgm;

    -- pgcrypto: 加密函数 (SHA/AES/RSA/digest 等)
    CREATE EXTENSION IF NOT EXISTS pgcrypto;

    -- hstore: 键值对存储
    CREATE EXTENSION IF NOT EXISTS hstore;

    -- 验证
    SELECT extname, extversion FROM pg_extension
    WHERE extname IN ('vector', 'pg_stat_statements', 'pg_trgm', 'pgcrypto', 'hstore')
    ORDER BY extname;
EOSQL

echo "[extensions] All extensions enabled successfully in database: $DB_NAME"
