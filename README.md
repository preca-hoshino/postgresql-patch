# PostgreSQL Patch — 常用扩展预编译镜像

基于 [1Panel PostgreSQL Dockerfile](https://github.com/1Panel-dev/appstore/tree/dev/apps/postgresql)，在构建时预编译并集成一组常用 PostgreSQL 扩展，涵盖向量搜索、表膨胀清理、执行计划干预、定时任务、地理空间等能力，同时保持与 1Panel PostgreSQL 100% 兼容。

镜像标签格式: `{pg_version}-alpine-patch`

## 概览

### 默认编译扩展

| 扩展 | 版本 | 用途 |
|------|------|------|
| pgvector | 0.8.2 | 向量存储与相似度搜索 |
| pg_repack | latest | 在线表膨胀清理，无锁重建表/索引 |
| pg_hint_plan | latest | 执行计划干预，强制指定索引/连接顺序 |

### 内核 contrib 扩展 (零编译，自动启用)

| 扩展 | 用途 |
|------|------|
| pg_stat_statements | SQL 执行统计，性能调优必备 |
| pg_trgm | 模糊文本搜索，三元组索引加速 `LIKE '%keyword%'` |
| pgcrypto | 加密函数 (SHA/AES/UUID) |
| hstore | 键值对存储类型 |
| pg_prewarm | 缓冲池预热，重启后快速恢复热数据 |
| auto_explain | 自动记录慢查询执行计划 |
| pg_visibility | 页面可见性检查，数据完整性诊断 |
| pg_freespacemap | 空闲空间地图，碎片分析 |
| pageinspect | 底层页面检查，深度调试 |



## 快速开始

```bash
# 拉取
docker pull ghcr.io/preca-hoshino/postgresql-patch:latest

# 运行
docker run -d \
  -p 5432:5432 \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=mydb \
  -v pgdata:/var/lib/postgresql/data \
  --name postgresql-patch \
  ghcr.io/preca-hoshino/postgresql-patch:latest

# 本地构建
docker build -t postgresql-patch ./build
```

### 构建参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `PG_VERSION` | `18.4` | PostgreSQL 版本 |
| `PGVECTOR_VERSION` | `0.8.2` | pgvector 版本 |

## 验证

```bash
docker exec -it postgresql-patch psql -U user -d mydb
```

```sql
-- 扩展列表
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- 向量操作
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;

-- HNSW 索引
CREATE INDEX ON items USING hnsw (embedding vector_l2_ops);

-- pg_stat_statements (SQL 统计)
SELECT query, calls, total_exec_time FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 5;

-- pg_trgm (模糊搜索)
CREATE INDEX ON items USING gin (embedding::text gin_trgm_ops);
SELECT * FROM items WHERE embedding::text LIKE '%1,2%';

-- pg_repack (表膨胀清理, 需安装 pg_repack 命令行工具)
-- pg_repack -d mydb -t items

-- pg_hint_plan (执行计划干预)
SET pg_hint_plan.enable_hint = on;
/*+ IndexScan(items) */ SELECT * FROM items WHERE id = 1;
```

## 向量搜索示例

```sql
CREATE TABLE documents (
    id bigserial PRIMARY KEY,
    content text,
    embedding vector(1536)
);

-- L2 距离
SELECT * FROM documents ORDER BY embedding <-> '[0.1,0.2,...]' LIMIT 5;

-- 余弦相似度
SELECT content, 1 - (embedding <=> '[0.1,0.2,...]') AS similarity
FROM documents ORDER BY embedding <=> '[0.1,0.2,...]' LIMIT 5;

-- 内积 (归一化向量)
SELECT * FROM documents ORDER BY embedding <#> '[0.1,0.2,...]' LIMIT 5;

-- HNSW 索引 (推荐)
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
SET hnsw.ef_search = 100;  -- 默认 40

-- IVFFlat 索引 (需要先有数据)
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
SET ivfflat.probes = 10;  -- 默认 1
```

混合搜索 (全文 + 向量):

```sql
ALTER TABLE documents ADD COLUMN ts tsvector
    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;
CREATE INDEX ON documents USING gin (ts);

SELECT id, content FROM documents
WHERE ts @@ plainto_tsquery('search terms')
ORDER BY embedding <=> '[0.1,0.2,...]' LIMIT 5;
```

## 1Panel 使用

将 1Panel PostgreSQL 应用的镜像替换为本项目镜像即可:

```yaml
# 原版 (1Panel 默认)
image: postgres:17.10-alpine

# 扩展版 (含全部扩展)
image: ghcr.io/preca-hoshino/postgresql-patch:17.10-alpine-patch
```

迁移细节见 [migration-guide.md](pgvector-migration-guide.md)。

## 支持的版本

| PG 版本 | 基础镜像 | 标签 |
|---------|----------|------|
| 18.4 | `postgres:18.4-alpine` | `18.4-alpine-patch` |
| 17.10 | `postgres:17.10-alpine` | `17.10-alpine-patch` |
| 16.14 | `postgres:16.14-alpine` | `16.14-alpine-patch` |
| 15.18 | `postgres:15.18-alpine` | `15.18-alpine-patch` |
| 14.23 | `postgres:14.23-alpine` | `14.23-alpine-patch` |

## CI/CD

GitHub Actions 四阶段流水线: 元数据 -> 构建(缓存) -> 推送 ghcr.io -> 拉取验证。

- 自动: 推送 `main`/`master` 且 `build/` 或 workflow 有变更
- 手动: Actions -> Run workflow
- 定时: 每周一 06:00 UTC
- PR: 仅构建验证，不推送

推送阶段内置指数退避重试以应对 ghcr.io 偶发超时。

## 项目结构

```
build/
  Dockerfile          # 多阶段构建，全部扩展预编译
  init-extensions.sh  # 自动初始化所有扩展 (contrib + 编译扩展)
.github/workflows/docker-build.yml
pgvector-migration-guide.md
```

## 许可证

[GPL-3.0](LICENSE) -- 基于 [1Panel PostgreSQL Dockerfile](https://github.com/1Panel-dev/appstore) 改造。

上游组件许可:

| 组件 | 许可证 |
|------|--------|
| PostgreSQL | PostgreSQL License |
| pgvector | PostgreSQL License |
| pg_repack | PostgreSQL License (BSD-3-Clause) |
| pg_cron | PostgreSQL License |
| pg_hint_plan | PostgreSQL License |
| PostGIS | GPL-2.0 |
| 1Panel Dockerfile | GPL-3.0 |

## 参考

- [pgvector](https://github.com/pgvector/pgvector) | [文档](https://github.com/pgvector/pgvector/blob/master/README.md)
- [pg_repack](https://github.com/reorg/pg_repack) | 在线表膨胀清理
- [pg_cron](https://github.com/citusdata/pg_cron) | 定时任务调度
- [pg_hint_plan](https://github.com/ossc-db/pg_hint_plan) | 执行计划干预
- [PostGIS](https://postgis.net/) | 地理空间数据
- [PostgreSQL Docker 镜像](https://hub.docker.com/_/postgres)
- [1Panel appstore](https://github.com/1Panel-dev/appstore)
