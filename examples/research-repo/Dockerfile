# Derived sandbox image for Python research repos (e.g. skeleton-research).
#
# The base pi-sandbox image ships node + git only (the research harness was
# built for JS/agent work). A skeleton-research checkout needs python3, make
# and the test deps, so we add them here. Everything else (the pi user, the
# baked plugins, ENTRYPOINT ["pi"]) is inherited unchanged.
FROM pi-sandbox:latest
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 python3-yaml python3-requests python3-feedparser \
      python3-pytest python3-hypothesis make \
 && rm -rf /var/lib/apt/lists/*
# stay root by default so the hardened launch can still choose --user pi:pi
USER root