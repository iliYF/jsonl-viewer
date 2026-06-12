# ============================================================
# JSONL Viewer - Dockerfile
# 多阶段构建，最终镜像仅包含运行时所需文件
# ============================================================

# -------------------- 阶段 1: 依赖安装 --------------------
FROM node:22-alpine AS deps
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@10 --activate

WORKDIR /app

# 复制依赖描述文件
COPY package.json pnpm-lock.yaml ./

# 安装生产依赖
RUN pnpm install --prod --frozen-lockfile

# -------------------- 阶段 2: 构建 --------------------
FROM node:22-alpine AS builder
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@10 --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .

# Next.js 构建
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

# -------------------- 阶段 3: 生产运行 --------------------
FROM node:22-alpine AS runner
LABEL org.opencontainers.image.title="JSONL Viewer"
LABEL org.opencontainers.image.description="A high-performance JSONL file viewer"
LABEL org.opencontainers.image.source="https://github.com/Sylinko/jsonl-viewer"

WORKDIR /app

# 创建非 root 用户
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# 复制生产依赖的 node_modules
COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules

# 复制构建产物
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./
COPY --from=builder --chown=nextjs:nodejs /app/next.config.js ./

# 环境变量
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 端口配置 - 通过 PORT 环境变量控制，默认 10001
ENV PORT=10001
EXPOSE ${PORT}

USER nextjs

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT} || exit 1

CMD ["sh", "-c", "npx next start --port ${PORT} --hostname 0.0.0.0"]
