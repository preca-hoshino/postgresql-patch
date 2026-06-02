# Dockerfile - PostgreSQL Patch (常用扩展预编译镜像)
# Based on https://github.com/1Panel-dev/appstore/tree/dev/apps/postgresql
# 预编译扩展: pgvector, pg_repack, pg_cron, pg_hint_plan, PostGIS
# 内核 contrib: pg_stat_statements, pg_trgm, pgcrypto, hstore, pg_prewarm 等
#
# 用法:
#   docker build -t postgresql-patch ./build

ARG PG_VERSION=18.4

# ===== Stage 1: Build extensions =====
FROM postgres:${PG_VERSION}-alpine AS builder

ARG PG_VERSION=18.4
ARG PGVECTOR_VERSION=0.8.2

RUN apk add --no-cache \
        build-base \
        postgresql-dev \
        git \
        zlib-dev \
        openssl-dev \
        lz4-dev \
        zstd-dev \
        gawk \
    && sed -i 's/with_llvm[[:space:]]*=[[:space:]]*yes/with_llvm = no/g' /usr/local/lib/postgresql/pgxs/src/Makefile.global \
    && ln -sf /usr/lib/libz.so /usr/local/lib/libz.so \
    && ln -sf /usr/lib/libssl.so /usr/local/lib/libssl.so \
    && ln -sf /usr/lib/libcrypto.so /usr/local/lib/libcrypto.so

# 1. pgvector (向量相似度搜索)
RUN cd /tmp \
    && git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git \
    && cd pgvector \
    && make OPTFLAGS="" -j$(nproc) \
    && make OPTFLAGS="" install \
    && echo "pgvector ${PGVECTOR_VERSION} built successfully"

# 2. pg_repack (在线表膨胀清理 — 无锁重建表/索引)
RUN cd /tmp \
    && git clone --depth 1 https://github.com/reorg/pg_repack.git \
    && cd pg_repack \
    && make -j$(nproc) \
    && make install \
    && echo "pg_repack built successfully"

# 3. pg_cron (定时任务调度 — 自动 VACUUM/维护/归档)
RUN cd /tmp \
    && git clone --depth 1 https://github.com/citusdata/pg_cron.git \
    && cd pg_cron \
    && make -j$(nproc) \
    && make install \
    && echo "pg_cron built successfully"

# 4. pg_hint_plan (执行计划干预 — 强制指定索引/连接顺序)
RUN cd /tmp \
    && git clone --depth 1 https://github.com/ossc-db/pg_hint_plan.git \
    && cd pg_hint_plan \
    && make -j$(nproc) \
    && make install \
    && echo "pg_hint_plan built successfully"

# 5. PostGIS (地理空间数据 — geometry/geography)
RUN apk add --no-cache \
        cmake \
        geos-dev \
        proj-dev \
        gdal-dev \
        json-c-dev \
        libxml2-dev \
        protobuf-c-dev \
    && cd /tmp \
    && wget -q https://download.osgeo.org/postgis/source/postgis-3.4.2.tar.gz \
    && tar xzf postgis-3.4.2.tar.gz \
    && cd postgis-3.4.2 \
    && ./configure --without-raster --without-topology \
    && make -j$(nproc) \
    && make install \
    && echo "PostGIS 3.4.2 built successfully"

# 收集所有编译产物到统一目录
RUN mkdir -p /tmp/extensions-build \
    && cp -a $(pg_config --sharedir)/extension/*.control /tmp/extensions-build/ 2>/dev/null || true \
    && cp -a $(pg_config --sharedir)/extension/*.sql /tmp/extensions-build/ 2>/dev/null || true \
    && cp -a $(pg_config --pkglibdir)/*.so /tmp/extensions-build/ 2>/dev/null || true \
    && echo "=== Collected extensions ===" \
    && ls -la /tmp/extensions-build/

# ===== Stage 2: Final image =====
FROM postgres:${PG_VERSION}-alpine

ARG PG_VERSION=18.4
ARG PGVECTOR_VERSION=0.8.2

LABEL maintainer="PostgreSQL Patch Community"
LABEL description="PostgreSQL ${PG_VERSION} + 常用扩展 (pgvector, pg_repack, pg_hint_plan, pg_cron, PostGIS, contrib)"
LABEL org.opencontainers.image.title="PostgreSQL Patch"
LABEL org.opencontainers.image.description="PostgreSQL ${PG_VERSION} with pre-compiled extensions for 1Panel"
LABEL org.opencontainers.image.version="${PG_VERSION}-alpine-patch"
LABEL pg.version="${PG_VERSION}"
LABEL extensions.pgvector.version="${PGVECTOR_VERSION}"

# Copy all extensions from builder
COPY --from=builder /tmp/extensions-build/*.so /usr/local/lib/postgresql/
COPY --from=builder /tmp/extensions-build/*.control /usr/local/share/postgresql/extension/
COPY --from=builder /tmp/extensions-build/*.sql /usr/local/share/postgresql/extension/

# Copy init script to auto-enable all extensions
COPY init-extensions.sh /docker-entrypoint-initdb.d/01-extensions.sh

# Verify extensions are loadable
RUN echo "=== Installed extensions ===" \
    && echo "--- pgvector ---" \
    && ls -la /usr/local/lib/postgresql/vector*.so \
    && ls -la /usr/local/share/postgresql/extension/vector*.control \
    && echo "--- pg_repack ---" \
    && ls -la /usr/local/lib/postgresql/pg_repack*.so \
    && echo "--- pg_cron ---" \
    && ls -la /usr/local/lib/postgresql/cron*.so \
    && echo "--- pg_hint_plan ---" \
    && ls -la /usr/local/lib/postgresql/hint_plan*.so \
    && echo "--- PostGIS ---" \
    && ls -la /usr/local/lib/postgresql/postgis*.so \
    && echo "=== All extensions verified ==="
