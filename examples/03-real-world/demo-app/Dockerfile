# Demo Dockerfile for buildah pipeline example

ARG NODE_VERSION=20
ARG BUILD_ENV=production
ARG APP_VERSION=1.0.0

FROM node:${NODE_VERSION}-alpine AS base

WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies (if any)
# RUN npm install

# Copy application code
COPY . .

# Build arguments available as env vars
ENV BUILD_ENV=${BUILD_ENV}
ENV APP_VERSION=${APP_VERSION}

# Run build
RUN npm run build

# Expose port
EXPOSE 3000

# Default command
CMD ["echo", "Demo app container - BUILD_ENV: ${BUILD_ENV}, VERSION: ${APP_VERSION}"]
