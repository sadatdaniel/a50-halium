# Build environment for the A50 kernel.
#
# Ubuntu 22.04 deliberately: it is what this port's kernel has always been
# built on, and Linux 4.14 with Proton Clang is old enough that newer host
# toolchains are a real risk rather than a neutral upgrade.
#
# The image intentionally contains no kernel source and no compiler toolchain.
# Both are fetched at build time at the commits pinned in kernel/source.lock,
# so the pin - not this image - is what determines the output.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc \
        bison \
        build-essential \
        ca-certificates \
        cpio \
        curl \
        device-tree-compiler \
        file \
        flex \
        gcc-aarch64-linux-gnu \
        git \
        kmod \
        libncurses-dev \
        libssl-dev \
        lz4 \
        python-is-python3 \
        python3 \
        rsync \
        unzip \
        wget \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
