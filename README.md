# PostgreSQL + pgvector (向量搜索) Docker 镜像

> 🧮 **向量搜索就绪的 PostgreSQL**: 基于 1Panel PostgreSQL 镜像，预装 [pgvector](https://github.com/pgvector/pgvector) 向量相似度搜索扩展

基于 [1Panel PostgreSQL Dockerfile](https://github.com/1Panel-dev/appstore/tree/dev/apps/postgresql)（使用官方 `postgres:alpine` 镜像），在构建时编译并集成 pgvector 扩展，开箱即用支持向量存储和相似度搜索。

> 版本命名对齐 1Panel appstore：`{pg_version}-pgvector-{pgvector_version}`
> 例：`17.10-pgvector-0.8.2`

## 特性

| 特性 | 状态 |
|------|------|
| PostgreSQL 14/15/16/17/18 | ✅ |
| pgvector 0.8.2 | ✅ |
| 向量相似度搜索 (L2/内积/余弦/L1) | ✅ |
| HNSW 近似最近邻索引 | ✅ |
| IVFFlat 索引 | ✅ |
| 半精度向量 (halfvec) | ✅ |
| 二值向量 (bit) | ✅ |
| 稀疏向量 (sparsevec) | ✅ |
| 二值量化 (binary quantization) | ✅ |
| 迭代索引扫描 (iterative scan) | ✅ |
| 与 1Panel PostgreSQL 100% 兼容 | ✅ |

## 快速开始

### 从 GitHub Container Registry 拉取

```bash
# 默认 PostgreSQL 17 + pgvector 0.8.2
docker pull ghcr.io/preca-hoshino/postgresql-pgvector:latest
```

### 运行

```bash
docker run -d \
  -p 5432:5432 \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=mydb \
  -v pgdata:/var/lib/postgresql/data \
  --name postgresql-pgvector \
  ghcr.io/preca-hoshino/postgresql-pgvector:latest
```

### 在 1Panel 中使用

将 1Panel PostgreSQL 应用的镜像替换为本项目镜像即可：

```yaml
# 原版 (1Panel 默认)
image: postgres:17.10-alpine

# pgvector 版
image: ghcr.io/preca-hoshino/postgresql-pgvector:17.10-pgvector-0.8.2

# PG 18 版
image: ghcr.io/preca-hoshino/postgresql-pgvector:18-pgvector-0.8.2
```

### 本地构建

```bash
# 默认 PG 17 + pgvector 0.8.2
docker build -t postgresql-pgvector-patch ./build

# PG 18 + pgvector 0.8.2
docker build \
  --build-arg PG_VERSION=18.4 \
  --build-arg PGVECTOR_VERSION=0.8.2 \
  -t postgresql-pgvector-patch:18-pgvector-0.8.2 \
  ./build

# 其他版本
docker build \
  --build-arg PG_VERSION=16.14 \
  --build-arg PGVECTOR_VERSION=0.8.2 \
  -t postgresql-pgvector-patch:16.14-pgvector-0.8.2 \
  ./build
```

## 验证

```bash
# 1. 进入容器
docker exec -it postgresql-pgvector psql -U user -d mydb

# 2. 验证扩展已安装
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
# → vector | 0.8.2

# 3. 测试向量操作
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');
SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;

# 4. 创建 HNSW 索引
CREATE INDEX ON items USING hnsw (embedding vector_l2_ops);

# 5. 测试余弦距离
SELECT 1 - (embedding <=> '[3,1,2]') AS cosine_similarity FROM items;
```

## pgvector 使用示例

### 基本向量搜索

```sql
-- 启用扩展 (已在 init 时自动完成)
CREATE EXTENSION IF NOT EXISTS vector;

-- 创建向量表
CREATE TABLE documents (
    id bigserial PRIMARY KEY,
    content text,
    embedding vector(1536)  -- OpenAI embedding 维度
);

-- 插入向量
INSERT INTO documents (content, embedding) VALUES
    ('PostgreSQL is great', '[0.1, 0.2, ...]'),
    ('pgvector enables search', '[0.3, 0.4, ...]');

-- L2 距离搜索 (精确)
SELECT * FROM documents ORDER BY embedding <-> '[0.15, 0.25, ...]' LIMIT 5;

-- 余弦相似度搜索
SELECT content, 1 - (embedding <=> '[0.15, 0.25, ...]') AS similarity
FROM documents
ORDER BY embedding <=> '[0.15, 0.25, ...]'
LIMIT 5;

-- 内积搜索 (归一化向量)
SELECT * FROM documents ORDER BY embedding <#> '[0.15, 0.25, ...]' LIMIT 5;
```

### HNSW 索引 (推荐)

```sql
-- 创建 HNSW 索引 (各距离函数)
CREATE INDEX ON documents USING hnsw (embedding vector_l2_ops);
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON documents USING hnsw (embedding vector_ip_ops);

-- 调优搜索参数
SET hnsw.ef_search = 100;  -- 默认 40，越大召回率越高但越慢
```

### IVFFlat 索引

```sql
-- 创建 IVFFlat 索引 (需要先有数据)
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- 调优搜索参数
SET ivfflat.probes = 10;  -- 默认 1，越大召回率越高但越慢
```

### 混合搜索 (全文 + 向量)

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

## 支持的 PostgreSQL 版本

| PG 版本 | Docker Hub 基础镜像 | 镜像标签 | 说明 |
|---------|-------------------|----------|------|
| 18.4 | `postgres:18.4-alpine` | `18-pgvector-0.8.2` | PostgreSQL 18 (最新) |
| 17.10 | `postgres:17.10-alpine` | `17.10-pgvector-0.8.2` | PostgreSQL 17 (推荐，与 1Panel 对齐) |
| 16.14 | `postgres:16.14-alpine` | `16.14-pgvector-0.8.2` | PostgreSQL 16 |
| 15.18 | `postgres:15.18-alpine` | `15.18-pgvector-0.8.2` | PostgreSQL 15 |
| 14.23 | `postgres:14.23-alpine` | `14.23-pgvector-0.8.2` | PostgreSQL 14 |

## CI/CD

本仓库使用 GitHub Actions 自动构建和推送镜像到 GitHub Container Registry，采用 **4 阶段流水线**：

| 阶段 | Job 名称 | 说明 |
|------|----------|------|
| 1 | `📋 准备 — 元数据` | 生成镜像标签、labels、版本号 |
| 2 | `🔨 构建 — 编译镜像` | 编译 Docker 镜像（缓存到 GitHub Actions Cache） |
| 3 | `📤 推送 — ghcr.io` | 登录 ghcr.io（自动重试），从缓存秒级重建并推送 |
| 4 | `✅ 验证 — 拉取测试` | 从 ghcr.io 拉取镜像，验证 pgvector 扩展 |

**触发条件：**

- **自动触发**: 推送到 `main`/`master` 分支（仅 `build/` 和 workflow 变更时），默认构建 PG 17 + PG 18
- **手动触发**: Actions → "🐳 Build & Push PostgreSQL + pgvector" → Run workflow（可指定单个版本或全部构建）
- **定时构建**: 每周一 6:00 UTC（保持基础镜像更新，同时构建 PG 17 和 PG 18）
- **PR 检查**: PR 只运行准备+构建（验证 Dockerfile 可编译，不推送）

**构建矩阵：** 默认同时构建 PG 17.10 和 PG 18.4 两个版本，各自独立的缓存和标签。手动触发时可指定单个 PG 版本。

**ghcr.io 登录重试：** 推送和验证阶段内置 5 次自动重试+指数退避，解决偶发性 `Client.Timeout` 问题。

## 项目结构

```
.
├── .github/workflows/
│   └── docker-build.yml          # CI/CD 工作流
├── build/
│   ├── Dockerfile                # 镜像构建文件
│   ├── init-pgvector.sh          # pgvector 自动初始化脚本
│   └── tmp/
│       ├── pre.sh                # 构建前脚本
│       └── default.sh            # 构建后脚本
├── pgvector-migration-guide.md   # 迁移指南
└── README.md
```

## 与原版 1Panel PostgreSQL 的区别

| 组件 | 原版 | pgvector 版 |
|------|------|-------------|
| pgvector 扩展 | ❌ 需手动安装 | ✅ 预装 + 自动启用 |
| 向量数据类型 | ❌ | ✅ vector, halfvec, bit, sparsevec |
| 向量索引 | ❌ | ✅ HNSW, IVFFlat |
| 向量距离函数 | ❌ | ✅ L2, 内积, 余弦, L1, Hamming, Jaccard |
| 镜像体积 | ~260MB (PG17 Alpine) | ~270MB (PG17 Alpine + pgvector) |
| 1Panel 兼容性 | ✅ | ✅ 100% 兼容，仅替换镜像名 |

## 许可证

本项目基于 [1Panel PostgreSQL Dockerfile](https://github.com/1Panel-dev/appstore)（GPL-3.0）改造，采用 [GNU General Public License v3.0](LICENSE)。

本项目打包的上游组件各自遵循原始许可协议：

| 组件 | 许可证 |
|------|--------|
| [PostgreSQL](https://www.postgresql.org) | PostgreSQL License (类 MIT) |
| [pgvector](https://github.com/pgvector/pgvector) | PostgreSQL License |
| [1Panel appstore Dockerfile](https://github.com/1Panel-dev/appstore) | GPL-3.0 |

## 参考

- [pgvector GitHub](https://github.com/pgvector/pgvector)
- [pgvector 文档](https://github.com/pgvector/pgvector/blob/master/README.md)
- [PostgreSQL 官方 Docker 镜像](https://hub.docker.com/_/postgres)
- [1Panel PostgreSQL Dockerfile](https://github.com/1Panel-dev/appstore/tree/dev/apps/postgresql)
- [1Panel 应用商店](https://github.com/1Panel-dev/appstore)
