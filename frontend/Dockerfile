# Build Vite app, serve static files with nginx
FROM node:20-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci 2>/dev/null || npm install --no-audit --no-fund

COPY . .

# Browser must reach API on the host (published port of service `api`)
ARG VITE_API_BASE_URL=http://localhost:3000/api
ARG VITE_UPLOADS_ORIGIN=http://localhost:3000
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_UPLOADS_ORIGIN=$VITE_UPLOADS_ORIGIN

RUN npm run build

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
