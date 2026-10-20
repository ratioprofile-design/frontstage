FROM swift:6.0.3-noble AS builder
WORKDIR /app/frontstage
COPY Package.swift ./
COPY Sources ./Sources
COPY Server/Package.swift Server/Package.resolved ./Server/
COPY Server/Sources ./Server/Sources
RUN swift build --package-path Server -c release --static-swift-stdlib -j 3 --force-resolved-versions

FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl libcurl4t64 libxml2 libicu74 libatomic1 libstdc++6 zlib1g && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 frontstage && useradd --uid 10001 --gid 10001 --create-home frontstage \
    && mkdir /data && chown frontstage:frontstage /data
WORKDIR /app
COPY --from=builder /app/frontstage/Server/.build/release/FrontstageServer ./FrontstageServer
COPY Server/Public ./Public
ENV FRONTSTAGE_DATA_DIR=/data
USER frontstage
VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD curl -fsS http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["./FrontstageServer", "serve", "--hostname", "0.0.0.0", "--port", "8080"]
