#!/bin/bash
# 生产服务器启动脚本
# 用法: PORT=10001 LOG_DIR=logs bash scripts/start.sh

PORT="${PORT:-10001}"
LOG_DIR="${LOG_DIR:-logs}"

# 切换到项目根目录（脚本所在目录的上一级）
cd "$(dirname "$0")/.." || exit 1

echo "🔍 检查旧 next 进程..."
pkill -f "next start" 2>/dev/null || true

echo "🔍 检查端口 ${PORT} 占用..."
lsof -ti:"${PORT}" 2>/dev/null | xargs kill -9 2>/dev/null || true

sleep 1

mkdir -p "${LOG_DIR}"

echo "🚀 后台启动生产服务器 (端口: ${PORT})..."
nohup npx pnpm start --hostname 0.0.0.0 --port "${PORT}" > "${LOG_DIR}/server.log" 2>&1 &
echo $! > .server.pid

echo "📝 进程 PID: $(cat .server.pid)"
