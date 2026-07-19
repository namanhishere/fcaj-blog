#!/bin/sh
set -e

PUML_DIR="/workspace/src"
OUT_DIR="${PUML_DIR}/../output"
PUML_PATTERN="${1:-*.puml}"

rm -rf "$OUT_DIR" 2>/dev/null || true
mkdir -p "$OUT_DIR"

echo "Compiling PlantUML diagrams..."
echo "  Source: $PUML_DIR/$PUML_PATTERN"
echo "  Output: $OUT_DIR"

for f in "$PUML_DIR"/$PUML_PATTERN; do
    [ -f "$f" ] || continue
    echo "  → $(basename "$f")"

    java -Djava.awt.headless=true \
        -jar /opt/plantuml/plantuml.jar \
        -graphvizdot /usr/bin/dot \
        -tpng \
        -o "$OUT_DIR" \
        "$f"

    java -Djava.awt.headless=true \
        -jar /opt/plantuml/plantuml.jar \
        -graphvizdot /usr/bin/dot \
        -tsvg \
        -o "$OUT_DIR" \
        "$f"
done

echo ""
echo "Done. Output:"
ls -lh "$OUT_DIR"/
