# Cloud Agent base image for my_new_app (Flutter + Firebase).
# Installs the stable Flutter SDK so agents can run:
#   flutter pub get | flutter analyze | flutter test
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Required by Cursor Cloud Agents (git checkout + sudo).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libglu1-mesa \
    sudo \
    unzip \
    xz-utils \
    zip \
    && rm -rf /var/lib/apt/lists/*

# Stable Flutter SDK (Dart ^3.12.0 required by pubspec.yaml).
ENV FLUTTER_ROOT=/opt/flutter
ENV PATH="${FLUTTER_ROOT}/bin:${FLUTTER_ROOT}/bin/cache/dart-sdk/bin:${PATH}"
RUN git clone https://github.com/flutter/flutter.git -b stable "${FLUTTER_ROOT}" \
    && git config --global --add safe.directory "${FLUTTER_ROOT}" \
    && flutter config --no-analytics \
    && flutter --version \
    && flutter precache

# Non-root user expected by Cloud Agents.
RUN useradd -m -s /bin/bash ubuntu \
    && usermod -aG sudo ubuntu \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

USER ubuntu
WORKDIR /home/ubuntu
