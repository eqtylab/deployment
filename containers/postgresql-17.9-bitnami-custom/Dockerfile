# syntax=docker/dockerfile:1.7

ARG BITNAMI_BASE_IMAGE=docker.io/bitnamilegacy/postgresql:17.6.0-debian-12-r4
ARG POSTGRESQL_VERSION=17.9
ARG POSTGRESQL_SHA256=3b9a62538a8da151e807a3ddb1198e8605f2032544d78f403ae883d27ecf1ee4
ARG POSTGRESQL_SOURCE_URL=https://ftp.postgresql.org/pub/source/v17.9/postgresql-17.9.tar.bz2

FROM ${BITNAMI_BASE_IMAGE} AS builder

ARG POSTGRESQL_VERSION
ARG POSTGRESQL_SHA256
ARG POSTGRESQL_SOURCE_URL

USER root

# Compile PostgreSQL 17.9 with the same feature set exposed by Bitnami's
# public 17.6 Debian image so we can retain Bitnami's runtime scripts/layout.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bison \
      build-essential \
      ca-certificates \
      curl \
      flex \
      libedit-dev \
      libicu-dev \
      libldap2-dev \
      libsasl2-dev \
      libssl-dev \
      libxml2-dev \
      libxslt1-dev \
      liblz4-dev \
      perl \
      pkg-config \
      uuid-dev \
      zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/postgresql-src \
 && mkdir -p /tmp/bitnami-extras/lib /tmp/bitnami-extras/licenses /tmp/bitnami-extras/share/extension \
 && cp -a /opt/bitnami/postgresql/lib/pgaudit.so /tmp/bitnami-extras/lib/ \
 && cp -a /opt/bitnami/postgresql/licenses/pgaudit-17.1.0.txt /tmp/bitnami-extras/licenses/ \
 && cp -a /opt/bitnami/postgresql/share/extension/pgaudit.control /tmp/bitnami-extras/share/extension/ \
 && cp -a /opt/bitnami/postgresql/share/extension/pgaudit--17.0--17.1.sql /tmp/bitnami-extras/share/extension/ \
 && cp -a /opt/bitnami/postgresql/share/extension/pgaudit--17.1.sql /tmp/bitnami-extras/share/extension/ \
 && curl -fsSL "${POSTGRESQL_SOURCE_URL}" -o /tmp/postgresql.tar.bz2 \
 && echo "${POSTGRESQL_SHA256}  /tmp/postgresql.tar.bz2" | sha256sum -c - \
 && tar -xjf /tmp/postgresql.tar.bz2 -C /tmp/postgresql-src --strip-components=1 \
 && rm -rf /opt/bitnami/postgresql \
 && cd /tmp/postgresql-src \
 && ./configure \
      --prefix=/opt/bitnami/postgresql \
      --with-libedit-preferred \
      --with-openssl \
      --with-libxml \
      --with-libxslt \
      --with-readline \
      --with-icu \
      --with-uuid=e2fs \
      --with-ldap \
      --with-lz4 \
      CFLAGS=-O2 \
      CXXFLAGS=-O2 \
      CC=gcc \
      LDFLAGS="-Wl,-rpath=/opt/bitnami/common/lib -L/opt/bitnami/common/lib -Wl,-rpath=/opt/bitnami/postgresql/lib -L/opt/bitnami/postgresql/lib" \
      CPPFLAGS="-I/opt/bitnami/common/include -I/opt/bitnami/postgresql/include" \
 && make -j"$(nproc)" world-bin \
 && make install-world-bin \
 && mkdir -p /opt/bitnami/postgresql/lib /opt/bitnami/postgresql/licenses /opt/bitnami/postgresql/share/extension \
 && cp -a /tmp/bitnami-extras/lib/pgaudit.so /opt/bitnami/postgresql/lib/ \
 && cp -a /tmp/bitnami-extras/licenses/pgaudit-17.1.0.txt /opt/bitnami/postgresql/licenses/ \
 && cp -a /tmp/bitnami-extras/share/extension/pgaudit.control /opt/bitnami/postgresql/share/extension/ \
 && cp -a /tmp/bitnami-extras/share/extension/pgaudit--17.0--17.1.sql /opt/bitnami/postgresql/share/extension/ \
 && cp -a /tmp/bitnami-extras/share/extension/pgaudit--17.1.sql /opt/bitnami/postgresql/share/extension/ \
 && strip /opt/bitnami/postgresql/bin/* /opt/bitnami/postgresql/lib/*.so* || true \
 && rm -rf /tmp/postgresql-src /tmp/postgresql.tar.bz2 /tmp/bitnami-extras

FROM ${BITNAMI_BASE_IMAGE}

ARG BITNAMI_BASE_IMAGE
ARG POSTGRESQL_VERSION
ARG POSTGRESQL_SOURCE_URL

USER root

# Bring the Debian 12 packages forward and drop optional tools that were in the
# original client scan while keeping Bitnami's entrypoint contract intact.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y \
 && DEBIAN_FRONTEND=noninteractive apt-get purge -y --auto-remove \
      gnupg2 \
      sqlite3 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN rm -rf /opt/bitnami/postgresql
COPY --from=builder /opt/bitnami/postgresql /opt/bitnami/postgresql

RUN /opt/bitnami/scripts/postgresql/postunpack.sh \
 && chmod -R g+rwX /opt/bitnami/postgresql \
 && find / -perm /6000 -type f -exec chmod a-s {} \; || true

LABEL org.opencontainers.image.title="bitnami-postgresql-custom" \
      org.opencontainers.image.description="Custom PostgreSQL 17.9 image using Bitnami runtime layout and entrypoint" \
      org.opencontainers.image.source="https://github.com/eqtylab/deployment/tree/main/containers/postgresql-17.9-bitnami-custom" \
      org.opencontainers.image.base.name="${BITNAMI_BASE_IMAGE}" \
      org.opencontainers.image.version="${POSTGRESQL_VERSION}"

ENV APP_VERSION="${POSTGRESQL_VERSION}" \
    PATH="/opt/bitnami/postgresql/bin:/opt/bitnami/common/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

USER 1001
