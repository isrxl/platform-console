#!/usr/bin/env bash
# Build app.zip with native wheels matching Azure App Service Python 3.11.
#
# app-cd must use actions/setup-python 3.11 before calling this script.
# Without a pinned 3.11 interpreter, ubuntu-latest defaults (3.12+) produce
# cp312 wheels that Azure 3.11 cannot import (ModuleNotFoundError: pyodbc).
#
# Usage: package-app.sh [output-zip-path]
set -euo pipefail

OUT_ZIP="${1:-app.zip}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/app"
PKG_ROOT=".python_packages/lib/site-packages"

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
pip install -r requirements.txt --target "$PKG_ROOT" --upgrade

if ! compgen -G "${PKG_ROOT}/pyodbc.cpython-${PY_ABI}-*.so" > /dev/null; then
  echo "ERROR: pyodbc native extension missing for cp${PY_ABI}" >&2
  ls -la "${PKG_ROOT}"/pyodbc* 2>/dev/null || true
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
