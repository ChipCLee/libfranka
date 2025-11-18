# -----------------------------------------------------------------------------
# Build a libfranka Debian package on Ubuntu 24.04 (amd64)
# Usage:
#   docker build -t libfranka-deb --build-arg LIBFRANKA_VERSION=0.17.0 .
#   cid=$(docker create libfranka-deb)
#   docker cp "$cid":/libfranka_${LIBFRANKA_VERSION:-0.17.0}_amd64.deb .
#   docker rm "$cid"
# -----------------------------------------------------------------------------

FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive

# Base build deps from libfranka README + common tools
# (build-essential, cmake, git, libpoco-dev, libeigen3-dev, libfmt-dev)
# Pinocchio is required for libfranka >= 0.14.0; install via robotpkg.
# See: libfranka README (deps + cpack), Pinocchio note.  (citations in chat)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git \
    libpoco-dev libeigen3-dev libfmt-dev \
    curl lsb-release ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Add robotpkg repo and install Pinocchio
RUN mkdir -p /etc/apt/keyrings \
 && curl -fsSL http://robotpkg.openrobots.org/packages/debian/robotpkg.asc \
    | tee /etc/apt/keyrings/robotpkg.asc >/dev/null \
 && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/robotpkg.asc] \
    http://robotpkg.openrobots.org/packages/debian/pub $(lsb_release -cs) robotpkg" \
    | tee /etc/apt/sources.list.d/robotpkg.list >/dev/null \
 && apt-get update && apt-get install -y --no-install-recommends \
    robotpkg-pinocchio \
 && rm -rf /var/lib/apt/lists/*

# Ensure CMake can find Pinocchio from robotpkg
ENV CMAKE_PREFIX_PATH=/opt/openrobots/lib/cmake

# Select libfranka version (defaults to latest release as of Oct 2025)
ARG LIBFRANKA_VERSION=0.17.0

# Get sources
WORKDIR /src
RUN git clone --recurse-submodules https://github.com/frankarobotics/libfranka.git
WORKDIR /src/libfranka
RUN git checkout ${LIBFRANKA_VERSION} \
 && git submodule update --init --recursive

# Configure, build, and package as .deb using CPack
WORKDIR /src/libfranka/build
RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF .. \
 && cmake --build . -j"$(nproc)" \
 && cpack -G DEB

RUN addgroup realtime && usermod -a -G realtime $(whoami) 

# Raise realtime group limits inside the container
RUN cat <<'EOF' >> /etc/security/limits.conf
@realtime soft rtprio 99
@realtime soft priority 99
@realtime soft memlock 102400
@realtime hard rtprio 99
@realtime hard priority 99
@realtime hard memlock 102400
EOF

# Minimal final image containing only the .deb for easy docker cp
# FROM scratch AS artifact
# ARG LIBFRANKA_VERSION=0.17.0
# # Copy and rename deterministically; wildcard matches the CPack output.
# COPY --from=build /src/libfranka/build/libfranka*.deb /libfranka_${LIBFRANKA_VERSION}_amd64.deb
