FROM eclipse-temurin:21-jre

RUN apt-get update && apt-get install -y --no-install-recommends \
    graphviz \
    fonts-dejavu \
    fontconfig \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG PLANTUML_VERSION=1.2026.6
RUN mkdir -p /opt/plantuml \
    && curl --fail --show-error --silent --location \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --connect-timeout 20 --max-time 300 \
    --output /opt/plantuml/plantuml.jar \
    "https://repo.maven.apache.org/maven2/net/sourceforge/plantuml/plantuml/${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"

WORKDIR /workspace

COPY entrypoint.sh /opt/plantuml/entrypoint.sh
RUN chmod +x /opt/plantuml/entrypoint.sh

ENTRYPOINT ["/opt/plantuml/entrypoint.sh"]
CMD ["*.puml"]
