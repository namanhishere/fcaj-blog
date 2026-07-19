# Diagrams

PlantUML diagrams for awsplace architecture. Sources live in `graph/src/`, output lands in `graph/output/`.

## With Docker

```bash
./graph/compile.sh                    # compile all .puml files
./graph/compile.sh architecture.puml  # compile a single file
```

This builds the image (first run) then compiles every `.puml` in `graph/src/` to PNG + SVG.

Manual equivalent:

```bash
docker build -t awsplace-diagram ./graph/
docker run --rm -v "$(pwd)/graph:/workspace" awsplace-diagram "*.puml"
```

## Without Docker

Prerequisites: Java 21+ and Graphviz (`dot`).

```bash
# download PlantUML (once)
curl --fail --show-error --silent --location \
    --output graph/plantuml.jar \
    https://repo.maven.apache.org/maven2/net/sourceforge/plantuml/plantuml/1.2026.6/plantuml-1.2026.6.jar

# compile
java -Djava.awt.headless=true \
     -jar graph/plantuml.jar \
     -graphvizdot /usr/bin/dot \
     -tpng -tsvg \
     -o graph/output \
     graph/src/*.puml
```

## Adding diagrams

Drop `.puml` files into `graph/src/`. AWS icons are available via:

```plantuml
!include <awslib/AWSCommon>
!include <awslib/Compute/all>
!include <awslib/NetworkingContentDelivery/all>
!include <awslib/Storage/all>
!include <awslib/Database/all>
!include <awslib/SecurityIdentityCompliance/all>
!include <awslib/ManagementGovernance/all>
!include <awslib/Containers/all>
!include <awslib/General/all>
```

Then use macros like `Lambda(...)`, `CloudFront(...)`, `DynamoDB(...)`, etc.

> **Known quirk:** macros starting with `API` (e.g. `APIGateway`) are rejected by PlantUML's parser. Use `AWSEntity` directly with a different sprite as a workaround.

## Files

| File | Purpose |
|------|---------|
| `src/*.puml` | Diagram sources |
| `Dockerfile` | `eclipse-temurin:21-jre` + graphviz, downloads plantuml.jar |
| `entrypoint.sh` | Compiles `.puml` → PNG + SVG |
| `compile.sh` | Convenience wrapper |
| `output/` | Rendered diagrams (gitignored) |

## Continuous integration

The site workflow compiles the diagrams before Hugo runs, publishes PNG and SVG
copies at `/images/diagrams/`, and attaches the generated files to the GitHub
Actions run together with the per-page link previews.
