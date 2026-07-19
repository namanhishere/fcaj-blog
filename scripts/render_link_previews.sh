#!/bin/sh
set -eu

PREVIEW_SCRIPT_DIRECTORY="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PREVIEW_PROJECT_DIRECTORY="$(dirname -- "$PREVIEW_SCRIPT_DIRECTORY")"
PREVIEW_PUBLIC_INPUT="${1:-public}"

if [ ! -d "$PREVIEW_PUBLIC_INPUT" ]; then
  echo "Link preview source directory does not exist: $PREVIEW_PUBLIC_INPUT" >&2
  exit 1
fi

PREVIEW_PUBLIC_DIRECTORY="$(CDPATH= cd -- "$PREVIEW_PUBLIC_INPUT" && pwd)"

docker build \
  --quiet \
  -t fcaj-link-preview \
  "$PREVIEW_PROJECT_DIRECTORY/link-preview"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$PREVIEW_PUBLIC_DIRECTORY:/site" \
  fcaj-link-preview
