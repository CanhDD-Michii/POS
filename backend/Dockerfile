# Backend API (Node 20; Debian slim avoids musl issues with native deps like bcrypt)
FROM node:20-bookworm-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev 2>/dev/null || npm install --omit=dev --no-audit --no-fund

COPY . .

# Persist uploaded files when a volume is mounted at /app/uploads
RUN mkdir -p uploads/products uploads/avatars

ENV NODE_ENV=production
EXPOSE 3000

CMD ["node", "server.js"]
