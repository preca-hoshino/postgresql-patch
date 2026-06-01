# PostgreSQL + pgvector 迁移方案

> **目标**：将 1Panel PostgreSQL Docker 镜像（官方 `postgres:alpine`）替换为预装 pgvector 扩展的版本，
> 实现向量相似度搜索能力，同时保持原 PostgreSQL 功能 100% 兼容。

---

## 一、核心变化

| 组件 | 原版 | 替换后 |
|------|------|--------|
| 基础镜像 | `postgres:17-alpine` | `postgres:17-alpine` (相同) |
| pgvector 扩展 | ❌ 不包含 | ✅ v0.8.2 预装 |
| 向量数据类型 | ❌ | ✅ vector, halfvec, bit, sparsevec |
| 向量索引 | ❌ | ✅ HNSW, IVFFlat |
| 向量距离函数 | ❌ | ✅ L2, 内积, 余弦, L1, Hamming, Jaccard |
| 自动初始化 | 创建默认数据库 | 创建默认数据库 + 自动启用 pgvector |
| 原有功能 | ✅ | ✅ 完全保留 |
| 镜像体积 | ~260 MB | ~270 MB (+10 MB) |

---

## 二、Dockerfile 修改要点

### 2.1 多阶段构建

```dockerfile
# Stage 1: 编译 pgvector (在 builder 阶段完成)
FROM postgres:${PG_VERSION}-alpine AS builder
RUN apk add --no-cache build-base postgresql-dev git \
    && git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git \
    && cd pgvector && make OPTFLAGS="" && make OPTFLAGS="" install

# Stage 2: 最终镜像 (只复制编译产物，不留编译工具)
FROM postgres:${PG_VERSION}-alpine
COPY --from=builder /tmp/pgvector-build/*.so /usr/local/lib/postgresql/
COPY --from=builder /tmp/pgvector-build/*.control /usr/local/share/postgresql/extension/
COPY --from=builder /tmp/pgvector-build/*.sql /usr/local/share/postgresql/extension/
```

> 多阶段构建确保最终镜像不包含 `build-base`、`postgresql-dev` 等编译依赖，保持镜像精简。

### 2.2 自动初始化脚本

```dockerfile
COPY init-pgvector.sh /docker-entrypoint-initdb.d/01-pgvector.sh
```

`init-pgvector.sh` 会在数据库首次初始化时自动执行：

```bash
#!/bin/bash
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL
```

> 注意：此脚本仅在 `docker volume` 首次创建时执行。已有数据库需手动执行 `CREATE EXTENSION vector;`。

### 2.3 编译选项说明

```
make OPTFLAGS=""   # 禁用 -march=native，确保跨平台兼容
```

> 不加 `OPTFLAGS=""` 会在编译机器的 CPU 指令集上优化，可能导致在其他机器上运行时出现 `Illegal instruction` 错误。

---

## 三、1Panel 使用方法

### 3.1 替换镜像（最简单方式）

在 1Panel 的 PostgreSQL 应用配置中，将镜像名替换为 pgvector 版本即可：

```yaml
# docker-compose.yml
services:
  postgres:
    # 原版
    # image: postgres:17.10-alpine
    # pgvector 版 (PG 17)
    image: ghcr.io/preca-hoshino/postgresql-patch:17.10-alpine-pgvector-0.8.2
    # pgvector 版 (PG 18)
    # image: ghcr.io/preca-hoshino/postgresql-patch:18.4-alpine-pgvector-0.8.2
    # 其余配置完全不变
```

### 3.2 新部署

1. 在 1Panel 中安装 PostgreSQL 应用
2. 修改 `docker-compose.yml`，替换镜像名
3. 启动容器，pgvector 已自动启用

### 3.3 已有数据库升级

```bash
# 1. 备份数据
docker exec -t postgres pg_dumpall -U user > backup.sql

# 2. 停止旧容器
docker stop postgres

# 3. 启动新容器 (使用 pgvector 镜像，挂载相同的 data volume)
docker run -d \
  -v pgdata:/var/lib/postgresql/data \
  ghcr.io/preca-hoshino/postgresql-patch:17.10-alpine-pgvector-0.8.2

# 4. 进入容器启用扩展
docker exec -it postgres psql -U user -d mydb
CREATE EXTENSION IF NOT EXISTS vector;
```

> 注意：新镜像的 `/docker-entrypoint-initdb.d/` 脚本只在数据库首次初始化时运行。
> 已有数据卷需要手动 `CREATE EXTENSION vector;`。

---

## 四、向量搜索配置示例

### 4.1 基本用法

```sql
-- 创建带向量列的表
CREATE TABLE documents (
    id bigserial PRIMARY KEY,
    content text,
    embedding vector(1536)  -- OpenAI embedding 维度
);

-- 插入向量
INSERT INTO documents (content, embedding) VALUES
    ('文档内容', '[0.1, 0.2, ...]');

-- 最近邻搜索 (L2 距离)
SELECT * FROM documents
ORDER BY embedding <-> '[0.15, 0.25, ...]'
LIMIT 5;

-- 余弦相似度搜索
SELECT content, 1 - (embedding <=> '[0.15, 0.25, ...]') AS similarity
FROM documents
ORDER BY embedding <=> '[0.15, 0.25, ...]'
LIMIT 5;
```

### 4.2 HNSW 索引 (推荐)

```sql
-- 创建索引 (各距离函数选一个)
CREATE INDEX ON documents USING hnsw (embedding vector_l2_ops);
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON documents USING hnsw (embedding vector_ip_ops);

-- 调优: 增大 ef_search 可提高召回率
SET hnsw.ef_search = 100;

-- 查看索引构建进度
SELECT phase, round(100.0 * blocks_done / nullif(blocks_total, 0), 1) AS "%"
FROM pg_stat_progress_create_index;
```

### 4.3 IVFFlat 索引

```sql
-- 需要先有一定数据量
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- 调优: 增大 probes 可提高召回率
SET ivfflat.probes = 10;
```

### 4.4 混合搜索 (全文 + 向量)

```sql
-- 添加全文搜索列
ALTER TABLE documents ADD COLUMN ts tsvector
    GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;
CREATE INDEX ON documents USING gin (ts);

-- 混合查询
SELECT id, content
FROM documents
WHERE ts @@ plainto_tsquery('search terms')
ORDER BY embedding <=> '[0.15, 0.25, ...]'
LIMIT 5;
```

---

## 五、风险控制

| 检查项 | 状态 |
|--------|------|
| 原有 PostgreSQL 功能 | ✅ 100% 兼容，pgvector 是纯扩展 |
| 1Panel 数据卷 | ✅ 数据目录结构不变 |
| 1Panel 环境变量 | ✅ POSTGRES_USER/PASSWORD/DB 不变 |
| PostgreSQL 复制 | ✅ pgvector 使用 WAL，支持流复制 |
| 已有数据安全性 | ✅ 扩展只添加新类型，不修改现有表 |
| 镜像体积 | ✅ 仅增加 ~10MB |
| 升级路径 | ✅ 可随时切换回原版镜像 |

---

## 六、验证步骤

```bash
# 1. 验证 pgvector 扩展已安装
docker exec -it pgvector psql -U user -d mydb -c \
  "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"
# → vector | 0.8.2

# 2. 验证向量类型可用
docker exec -it pgvector psql -U user -d mydb -c \
  "SELECT '[1,2,3]'::vector;"

# 3. 验证向量搜索
docker exec -it pgvector psql -U user -d mydb -c "
  CREATE TABLE test_vectors (id serial, v vector(3));
  INSERT INTO test_vectors (v) VALUES ('[1,2,3]'), ('[4,5,6]'), ('[1,2,4]');
  SELECT * FROM test_vectors ORDER BY v <-> '[1,2,3]' LIMIT 3;
  DROP TABLE test_vectors;
"

# 4. 验证 HNSW 索引
docker exec -it pgvector psql -U user -d mydb -c "
  CREATE TABLE test_hnsw (id serial, v vector(3));
  CREATE INDEX ON test_hnsw USING hnsw (v vector_l2_ops);
  DROP TABLE test_hnsw;
"

# 5. 查看已安装的所有扩展
docker exec -it pgvector psql -U user -d mydb -c \
  "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

---

## 七、CI/CD 自动构建

### 7.1 GitHub Actions 工作流

本仓库包含一套完整的 GitHub Actions 工作流（`.github/workflows/docker-build.yml`），用于自动构建和发布镜像。

```bash
# 1. 创建新仓库并推送代码
git init
git add -A
git commit -m "feat: PostgreSQL + pgvector Docker image with CI/CD"
git remote add origin https://github.com/preca-hoshino/postgresql-patch.git
git push -u origin main
```

### 7.2 触发方式

| 触发方式 | 说明 |
|---------|------|
| 推送到 main/master | 自动构建并推送镜像到 ghcr.io（默认构建 PG 17 + PG 18） |
| PR 到 main/master | 构建但不推送（验证 Dockerfile 可构建） |
| workflow_dispatch | 手动触发，可指定单个版本或全部构建 |
| 定时 (每周一 6:00 UTC) | 自动重建以保持基础镜像更新（同时构建 PG 17 和 PG 18） |

### 7.3 镜像标签

```
ghcr.io/preca-hoshino/postgresql-patch:latest
ghcr.io/preca-hoshino/postgresql-patch:18.4-alpine-pgvector-0.8.2
ghcr.io/preca-hoshino/postgresql-patch:17.10-alpine-pgvector-0.8.2
ghcr.io/preca-hoshino/postgresql-patch:16.14-alpine-pgvector-0.8.2
ghcr.io/preca-hoshino/postgresql-patch:15.18-alpine-pgvector-0.8.2
ghcr.io/preca-hoshino/postgresql-patch:14.23-alpine-pgvector-0.8.2
```

### 7.4 手动触发构建

1. 进入 GitHub 仓库 → Actions → "🐳 Build & Push PostgreSQL + pgvector"
2. 点击 "Run workflow"
3. 可选：指定 `pg_version`（如 `18.4` 或 `18`）和 `pgvector_version`
4. 点击 "Run workflow" 执行

> 不指定 `pg_version` 时，将同时构建 PG 17.10 和 PG 18.4 两个版本。

### 7.5 拉取和使用

```bash
# 拉取镜像
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
```

---

## 八、参考链接

- pgvector GitHub：https://github.com/pgvector/pgvector
- pgvector 文档：https://github.com/pgvector/pgvector/blob/master/README.md
- PostgreSQL 官方 Docker 镜像：https://hub.docker.com/_/postgres
- 1Panel PostgreSQL Dockerfile：`apps/postgresql/17.10-alpine/docker-compose.yml`
- 本项目仓库：`build/Dockerfile` + `.github/workflows/docker-build.yml`
