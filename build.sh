#!/bin/bash

# Speech2Write release build (SwiftPM).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${PROJECT_DIR}"

swift build -c release

echo "Build complete: ${PROJECT_DIR}/.build/release"
echo "To assemble a distributable app bundle, run ./package.sh"
