# PostgreSQL + pgvector

基于 [1Panel PostgreSQL Dockerfile](https://github.com/1Panel-dev/appstore/tree/dev/apps/postgresql)，在构建时编译并集成 [pgvector](https://github.com/pgvector/pgvector) 扩展，提供向量存储与相似度搜索能力，同时预装常用内置扩展，保持与 1Panel PostgreSQL 100% 兼容。

版本标签格式: `{pg_version}-alpine-pgvector-{pgvector_version}`

## 概览

| 组件 | 版本 | 说明 |
|------|------|------|
| PostgreSQL | 14 / 15 / 16 / 17 / 18 | 基础数据库 |
| pgvector | 0.8.2 | 向量相似度搜索 (编译安装) |
| pg_stat_statements | 内置 | SQL 执行统计与性能分析 |
| pg_trgm | 内置 | 模糊文本搜索 (支持三元组索引加速) |
| pgcrypto | 内置 | 加密函数 (SHA/AES/RSA 等) |
| hstore | 内置 | 键值对存储 |

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

构建参数可通过 `--build-arg` 覆盖，参见 [Dockerfile](build/Dockerfile) 中的 `ARG` 声明。

## 验证

```bash
docker exec -it postgresql-patch psql -U user -d mydb
```

```sql
-- 查看所有已启用的扩展
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- pgvector: 向量操作
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
CREATE INDEX ON items USING hnsw (embedding vector_l2_ops);

-- pg_stat_statements: 查看最慢的 SQL
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;

-- pg_trgm: 模糊搜索
SELECT similarity('hello world', 'hello word');  -- 相似度计算
CREATE INDEX ON items USING gin (name gin_trgm_ops);  -- 加速 LIKE 查询

-- pgcrypto: 加密
SELECT encode(digest('hello', 'sha256'), 'hex');
SELECT gen_random_uuid();

-- hstore: 键值对
SELECT 'a=>1, b=>2'::hstore -> 'a';  -- 取值
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

# pgvector 版
image: ghcr.io/preca-hoshino/postgresql-patch:17.10-alpine-pgvector-0.8.2
```

迁移细节见 [pgvector-migration-guide.md](pgvector-migration-guide.md)。

## 支持的版本

| PG 版本 | 基础镜像 | 标签 |
|---------|----------|------|
| 18.4 | `postgres:18.4-alpine` | `18.4-alpine-pgvector-0.8.2` |
| 17.10 | `postgres:17.10-alpine` | `17.10-alpine-pgvector-0.8.2` |
| 16.14 | `postgres:16.14-alpine` | `16.14-alpine-pgvector-0.8.2` |
| 15.18 | `postgres:15.18-alpine` | `15.18-alpine-pgvector-0.8.2` |
| 14.23 | `postgres:14.23-alpine` | `14.23-alpine-pgvector-0.8.2` |

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
  Dockerfile
  init-pgvector.sh
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
| 1Panel Dockerfile | GPL-3.0 |

## 参考

- [pgvector](https://github.com/pgvector/pgvector) | [文档](https://github.com/pgvector/pgvector/blob/master/README.md)
- [PostgreSQL Docker 镜像](https://hub.docker.com/_/postgres)
- [1Panel appstore](https://github.com/1Panel-dev/appstore)
