#!/usr/bin/env bash
# Runs inside debian:trixie arm64 (the seats' Raspberry Pi OS trixie): builds d2d and mpq-cat from /src (upstream + patches),
# runs upstream's tests, copies the binaries and what they need to /out. Packages as upstream's tools/validate-linux.Dockerfile.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq --no-install-recommends \
  ca-certificates cmake ninja-build build-essential pkg-config git python3 findutils \
  libsdl3-dev libopenal-dev zlib1g-dev libbz2-dev libstorm-dev libcurl4-openssl-dev qt6-base-dev libgl1-mesa-dev >/dev/null
FLAGS="-O3 -mcpu=cortex-a76"   # Raspberry Pi 5
cmake -S /src -B /build -G Ninja -DCMAKE_BUILD_TYPE=Release -DD2D_WERROR=OFF -DD2D_CCACHE=OFF \
  -DCMAKE_CXX_FLAGS="$FLAGS" -DCMAKE_C_FLAGS="$FLAGS" > /out/cmake.log
cmake --build /build -j"$(nproc)" > /out/build.log 2>&1 || { grep -E "error:|FAILED:" /out/build.log | head -40; exit 1; }
ctest --test-dir /build -j"$(nproc)" --output-on-failure > /out/tests.log 2>&1 || { tail -40 /out/tests.log; exit 1; }
grep "tests passed" /out/tests.log
cp /build/apps/d2d/d2d /build/tools/mpq-cat/mpq-cat /out/
if ldd /out/d2d /out/mpq-cat | grep "not found"; then exit 1; fi
# the Debian packages of the libraries the binaries ask for (Ansible installs these on the seats)
objdump -p /out/d2d /out/mpq-cat | awk '/NEEDED/{print $2}' | sort -u | while read -r lib; do dpkg -S "*/$lib"; done \
  | cut -d: -f1 | sort -u | grep -vE '^(libc6|libgcc-s1|libstdc\+\+6)$' > /out/RUNTIME-PACKAGES
cat /out/RUNTIME-PACKAGES | xargs echo "runtime packages:"
