FROM node:22-slim

ARG CLAUDE_CODE_VERSION=latest
RUN apt-get update && apt-get install -y --no-install-recommends tzdata ca-certificates jq \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
    && npm cache clean --force

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER node
WORKDIR /home/node
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
