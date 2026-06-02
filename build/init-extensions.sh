#!/bin/bash
# init-extensions.sh — 自动启用所有预装扩展
# 该脚本被复制到 /docker-entrypoint-initdb.d/，在 PostgreSQL 首次初始化时自动执行
#
# 扩展清单:
#   内核 contrib (零编译): pg_stat_statements, pg_trgm, pgcrypto, hstore,
#                          pg_prewarm, auto_explain, pg_visibility, pg_freespacemap, pageinspect
#   编译扩展: pgvector, pg_repack, pg_hint_plan, [pg_cron], [PostGIS]
#   方括号表示需要 build-arg 启用

set -e

DB_NAME="${POSTGRES_DB:-postgres}"

echo "[extensions] Initializing extensions in database: $DB_NAME"

# ===== 1. shared_preload_libraries 配置 =====
cat >> "$PGDATA/postgresql.conf" <<EOF

# === Extensions (auto-configured by init script) ===
shared_preload_libraries = 'pg_stat_statements, auto_explain, pg_cron'

# pg_stat_statements: SQL 执行统计
pg_stat_statements.track = all
pg_stat_statements.max = 10000

# auto_explain: 自动记录慢查询执行计划
auto_explain.log_min_duration = '1s'
auto_explain.log_analyze = true

# pg_cron: 定时任务调度 (参数在 pg_cron.so 加载后生效)
cron.database_name = '${DB_NAME}'
EOF

echo "[extensions] shared_preload_libraries = pg_stat_statements, auto_explain, pg_cron"

# ===== 2. 内核 contrib 扩展 (CREATE EXTENSION) =====
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
    -- 向量相似度搜索
    CREATE EXTENSION IF NOT EXISTS vector;

    -- SQL 执行统计 (性能调优必备)
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

    -- 模糊文本搜索 (三元组索引, LIKE '%keyword%' 加速)
    CREATE EXTENSION IF NOT EXISTS pg_trgm;

    -- 加密函数 (SHA/AES/UUID)
    CREATE EXTENSION IF NOT EXISTS pgcrypto;

    -- 键值对存储类型
    CREATE EXTENSION IF NOT EXISTS hstore;

    -- 缓冲池预热 (重启后快速恢复热数据)
    CREATE EXTENSION IF NOT EXISTS pg_prewarm;

    -- 页面可见性检查 (数据完整性诊断)
    CREATE EXTENSION IF NOT EXISTS pg_visibility;

    -- 空闲空间地图 (碎片分析)
    CREATE EXTENSION IF NOT EXISTS pg_freespacemap;

    -- 底层页面检查 (深度调试)
    CREATE EXTENSION IF NOT EXISTS pageinspect;
EOSQL

echo "[extensions] Contrib extensions enabled"

# ===== 3. 编译扩展 =====

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
    -- 在线表膨胀清理 (无锁)
    CREATE EXTENSION IF NOT EXISTS pg_repack;

    -- 执行计划干预 (强制索引/连接顺序)
    CREATE EXTENSION IF NOT EXISTS pg_hint_plan;

    -- 定时任务调度
    CREATE EXTENSION IF NOT EXISTS pg_cron;

    -- 地理空间数据
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS postgis_topology;
EOSQL

echo "[extensions] Compiled extensions enabled"

# ===== 4. 验证 =====
echo "[extensions] Installed extensions:"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" \
    -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"

echo "[extensions] All extensions initialized successfully in database: $DB_NAME"
