# TODO: zpu gcc, verilator, python
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    bison \
    flex \
    git \
    python3 \
    python3-pip \
    verilator \
    libelf-dev \
    cmake \
    clang \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace