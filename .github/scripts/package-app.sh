#!/usr/bin/env bash
# Build app.zip with native wheels matching Azure App Service Python 3.11.
#
# app-cd must use actions/setup-python 3.11 before calling this script.
# Without a pinned 3.11 interpreter, ubuntu-latest defaults (3.12+) produce
# cp312 wheels that Azure 3.11 cannot import (ModuleNotFoundError: pyodbc).
#
# Two axes must match the App Service runtime:
#   1. Python ABI  — pinned to cp311 via actions/setup-python (above).
#   2. glibc level — ubuntu-latest (glibc 2.39) would otherwise pull
#      manylinux_2_34 wheels for native deps (e.g. cryptography), whose Rust
#      extension needs GLIBC_2.33+. App Service Python 3.11 (Oryx/Debian) ships
#      glibc 2.31, so those fail at boot with:
#        ImportError: ... version `GLIBC_2.33' not found ... _rust.abi3.so
#      We constrain pip to manylinux tags built against glibc <= 2.28 and assert
#      it below, turning a runtime 503 into a build-time failure.
#
# Usage: package-app.sh [output-zip-path]
set -euo pipefail

OUT_ZIP="${1:-app.zip}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"
PKG_ROOT=".python_packages/lib/site-packages"
# Highest glibc symbol App Service can satisfy is 2.31; our pinned manylinux
# wheels reference at most 2.28, so that is the ceiling the guard enforces.
MAX_GLIBC="2.28"

PY_MINOR="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$PY_MINOR" != "3.11" ]]; then
  echo "ERROR: Python 3.11 required (Azure App Service); found ${PY_MINOR}" >&2
  exit 1
fi

PY_ABI="$(python -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')"

if command -v apt-get >/dev/null 2>&1; then
  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update -qq
    apt-get install -y -qq unixodbc-dev
  else
    sudo apt-get update -qq
    sudo apt-get install -y -qq unixodbc-dev
  fi
fi

cd "$APP_DIR"
python -m pip install --upgrade pip
rm -rf .python_packages
# --platform pins native wheels to glibc <= 2.28 (see header). Multiple tags are
# required because pip treats --platform literally: pyodbc/cffi ship
# manylinux2014 (2.17) wheels while cryptography ships manylinux_2_28. Omitting a
# tag here, or adding manylinux_2_34, reintroduces the GLIBC_2.33 boot failure.
# --only-binary=:all: is mandatory whenever --platform is used.
pip install -r requirements.txt --target "$PKG_ROOT" --upgrade \
  --only-binary=:all: \
  --platform manylinux2014_x86_64 \
  --platform manylinux_2_17_x86_64 \
  --platform manylinux_2_28_x86_64

if ! compgen -G "${PKG_ROOT}/pyodbc.cpython-${PY_ABI}-*.so" > /dev/null; then
  echo "ERROR: pyodbc native extension missing for cp${PY_ABI}" >&2
  ls -la "${PKG_ROOT}"/pyodbc* 2>/dev/null || true
  exit 1
fi

# Guard: no native wheel may require a glibc newer than App Service provides.
# The runner's glibc (2.39) hides this at import time, so inspect the ELF symbol
# versions directly and fail the build if any exceed MAX_GLIBC.
HIGHEST_GLIBC="$(find "$PKG_ROOT" -name '*.so' -print0 \
  | xargs -0 -r objdump -T 2>/dev/null \
  | grep -oE 'GLIBC_2\.[0-9]+' \
  | sort -V | tail -1 | sed 's/GLIBC_//')"
if [[ -n "$HIGHEST_GLIBC" ]] \
  && [[ "$(printf '%s\n%s\n' "$MAX_GLIBC" "$HIGHEST_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]]; then
  echo "ERROR: a native wheel requires GLIBC_${HIGHEST_GLIBC} > ${MAX_GLIBC} (too new for App Service)" >&2
  find "$PKG_ROOT" -name '*.so' -exec sh -c \
    'objdump -T "$1" 2>/dev/null | grep -q "GLIBC_'"${HIGHEST_GLIBC}"'" && echo "  $1"' _ {} \; >&2 || true
  exit 1
fi

export PYTHONPATH="$(pwd)/${PKG_ROOT}"
export PYTHONNOUSERSITE=1
python -c "import pyodbc, flask, gunicorn; print('deps OK')"
python -c "import app; print('app import OK')"

if [[ "$OUT_ZIP" != /* ]]; then
  OUT_ZIP="$REPO_ROOT/$OUT_ZIP"
fi
rm -f "$OUT_ZIP"
# Exclude Windows binaries if a developer ran pip locally on the same tree.
zip -r "$OUT_ZIP" . -x "tests/*" "*.pyc" "__pycache__/*" "*.pyd"

echo "Packaged $(du -h "$OUT_ZIP" | cut -f1) -> $OUT_ZIP"
