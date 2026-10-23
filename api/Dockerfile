# The API server's image, for Cloud Run (.github/workflows/deploy.yml). Build from api/:
#   docker build -t wildcard-api api
FROM node:22.20.0-slim AS build
WORKDIR /api
RUN npm install --global pnpm@10.28.0
COPY . .
ENV CI=true
RUN pnpm install --frozen-lockfile && pnpm build
# Only what the server needs at run time: drop the dev tools and install production packages.
RUN rm -rf node_modules apps/*/node_modules packages/*/node_modules && pnpm install --frozen-lockfile --prod

FROM node:22.20.0-slim
WORKDIR /api
ENV NODE_ENV=production
COPY --from=build /api /api
USER node
EXPOSE 8080
CMD ["node", "apps/server/dist/src/main.js"]
