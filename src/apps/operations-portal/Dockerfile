FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY src/apps/customer-portal/package.json ./src/apps/customer-portal/
COPY src/apps/operations-portal/package.json ./src/apps/operations-portal/
RUN npm ci
COPY generated/typescript ./generated/typescript
COPY src/apps/operations-portal ./src/apps/operations-portal
ARG VITE_API_BASE_URL=http://localhost:8083
ARG VITE_TELEMETRY_ENABLED=false
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}
ENV VITE_TELEMETRY_ENABLED=${VITE_TELEMETRY_ENABLED}
RUN npm run build -w @edgemint/operations-portal

FROM nginx:1.27-alpine
COPY src/apps/operations-portal/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/src/apps/operations-portal/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK CMD wget -qO- http://127.0.0.1/healthz >/dev/null || exit 1
