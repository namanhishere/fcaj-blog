FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    librsvg2-bin \
    fonts-inter \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /site

COPY entrypoint.sh /usr/local/bin/render-link-previews
RUN chmod +x /usr/local/bin/render-link-previews

ENTRYPOINT ["/usr/local/bin/render-link-previews"]
