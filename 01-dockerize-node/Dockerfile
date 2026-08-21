# ---- build stage -------------------------------------------------------------
# Pinned to an exact minor version. ":alpine" or ":latest" means the image that
# builds today can fail next month for reasons unrelated to your code.
FROM node:20.18-alpine AS builder

WORKDIR /app

# Manifests first, source second. Reversed, every source change invalidates the
# dependency layer and a 40-second build becomes a 6-minute one.
COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---- runtime stage -----------------------------------------------------------
FROM node:20.18-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production

# tini reaps zombies and forwards signals. Node as PID 1 ignores SIGTERM, so the
# container is SIGKILLed after the 10s grace period — cutting in-flight requests.
RUN apk add --no-cache tini

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# --chown avoids a second layer just to fix ownership.
COPY --from=builder --chown=node:node /app/dist ./dist

# A breached root container owns the host through any mounted volume.
USER node

EXPOSE 3000

# Without a healthcheck, nothing can distinguish "running" from "hung", and
# compose's `condition: service_healthy` has nothing to wait on.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/main.js"]
