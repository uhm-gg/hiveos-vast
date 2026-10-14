# syntax=docker/dockerfile:1
#
# hiveos-vast: the official HiveOS client in a container, for rented GPUs on
# Vast.ai (works on other Docker-based GPU clouds too).
#
# The HiveOS client is installed from HiveOS's own signed apt repository, so the
# image always carries the genuine client. Container-specific helpers live in
# rootfs/ and are explained in README.md.
#
#   docker build -t YOUR_DOCKERHUB_USER/hiveos-vast:latest .
#   docker build --build-arg HIVE_VERSION=0.6-231 -t YOUR_DOCKERHUB_USER/hiveos-vast:0.6-231 .

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
# Full fingerprint of the key that signs https://download.hiveos.farm/repo/binary
ARG HIVE_REPO_KEY=96663192AD0AC131DB93CA44817791619025A82D
# HiveOS client version to install, e.g. 0.6-231. Empty = newest in the repo.
ARG HIVE_VERSION=

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PATH=/hive/bin:/hive/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LC_NUMERIC=C

# Container helpers go in first: HiveOS's package scripts call systemctl.
COPY rootfs/ /

# Base tools + HiveOS repository (key checked against its full fingerprint).
RUN set -eux; \
    chmod 0755 /usr/local/bin/* /usr/local/sbin/* /usr/local/lib/hiveos-vast/*; \
    ln -s poweroff /usr/local/sbin/shutdown; \
    ln -s poweroff /usr/local/sbin/halt; \
    # apt runs package scripts with PATH=/usr/sbin:/usr/bin:/sbin:/bin; let them
    # see the container helpers too (HiveOS installs miners through apt).
    echo 'DPkg::Path "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";' \
        > /etc/apt/apt.conf.d/90hiveos-vast-path; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg tini cron logrotate screen sudo procps kmod \
        pciutils usbutils dmidecode iproute2 net-tools lsb-release unzip xz-utils; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${HIVE_REPO_KEY}" -o /tmp/hiveos.asc; \
    fpr="$(gpg --show-keys --with-colons /tmp/hiveos.asc | awk -F: '/^fpr:/ {print $10; exit}')"; \
    if [ "$fpr" != "$HIVE_REPO_KEY" ]; then echo "Unexpected HiveOS repository key: $fpr" >&2; exit 1; fi; \
    gpg --dearmor -o /etc/apt/trusted.gpg.d/hiveos.gpg /tmp/hiveos.asc; \
    rm -f /tmp/hiveos.asc; \
    echo "deb https://download.hiveos.farm/repo/binary/ /" > /etc/apt/sources.list.d/hiverepo.list; \
    rm -rf /var/lib/apt/lists/*

# The HiveOS client itself.
RUN set -eux; \
    useradd -m -s /bin/bash user; \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections; \
    apt-get update; \
    apt-get install -y --no-install-recommends "hive${HIVE_VERSION:+=$HIVE_VERSION}"; \
    dpkg-query -W -f='${Version}\n' hive > /etc/hiveos-version; \
    # Tools that need the physical machine are replaced. dpkg-divert keeps the
    # originals as <name>.hive and keeps these replacements across HiveOS upgrades.
    for tool in nvidia-oc amd-oc intel-oc tweakers autofan; do \
        dpkg-divert --local --rename --divert "/hive/sbin/$tool.hive" --add "/hive/sbin/$tool"; \
        ln -s /usr/local/lib/hiveos-vast/hw-disabled "/hive/sbin/$tool"; \
    done; \
    for tool in nvidia-driver-update sreboot; do \
        dpkg-divert --local --rename --divert "/hive/sbin/$tool.hive" --add "/hive/sbin/$tool"; \
        ln -s "/usr/local/lib/hiveos-vast/$tool" "/hive/sbin/$tool"; \
    done; \
    # OpenCL miners look the NVIDIA driver up through this ICD entry; the library
    # itself is mounted into the container by the NVIDIA container runtime.
    mkdir -p /etc/OpenCL/vendors; \
    echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd; \
    mkdir -p /hive-config /var/log/miner; \
    cp -rn /hive/etc/hive-config.stub/. /hive-config/; \
    rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.title="hiveos-vast" \
      org.opencontainers.image.description="Official HiveOS client in a container for rented GPUs (Vast.ai). Set FARM_HASH, or RIG_ID + RIG_PASSWD."

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hiveos-vast-start"]
