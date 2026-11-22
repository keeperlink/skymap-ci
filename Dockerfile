# CI-only Ubuntu environment: native distribution Python, dpkg, sudoers,
# cron and transport tooling. No project dependencies or secrets are baked in.
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} AS runtime-base

ARG EXPECTED_PYTHON=3.12
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates coreutils cron curl dpkg findutils git \
        gzip openssh-client openssl passwd python3 python3-pip python3-venv \
        rsync sudo tar xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && test "$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" = "$EXPECTED_PYTHON" \
    && test -x /usr/bin/python3 \
    && groupadd --gid 10001 ci \
    && useradd --uid 10001 --gid 10001 --create-home --home-dir /home/ci --shell /bin/bash ci

LABEL org.opencontainers.image.title="SKY-MAP CI Ubuntu environment" \
      org.opencontainers.image.description="Native Python and Debian package validation tools on Ubuntu"

ENV LANG=C.UTF-8 HOME=/home/ci
USER 10001:10001
WORKDIR /home/ci
CMD ["/bin/bash"]
