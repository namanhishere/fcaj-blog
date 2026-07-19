#!/bin/sh
set -eu

# Build PlantUML diagrams via Docker.
# Usage: ./graph/compile.sh [pattern]
#   pattern defaults to "*.puml"

GRAPH_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

docker build --quiet -t fcaj-plantuml "$GRAPH_DIRECTORY"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$GRAPH_DIRECTORY:/workspace" \
  fcaj-plantuml \
  "${1:-*.puml}"
