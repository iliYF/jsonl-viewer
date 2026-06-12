#!/bin/bash
# 生产服务器启动脚本
# 用法: PORT=10001 LOG_DIR=logs bash scripts/start.sh

PORT="${PORT:-10001}"
LOG_DIR="${LOG_DIR:-logs}"

# 切换到项目根目录（脚本所在目录的上一级）
cd "$(dirname "$0")/.." || exit 1

# ── 工具函数：检查端口是否被占用 ──────────────────────────
port_in_use() {
    if command -v ss > /dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -q ":${PORT} "
    elif command -v lsof > /dev/null 2>&1; then
        lsof -ti:"${PORT}" > /dev/null 2>&1
    elif command -v fuser > /dev/null 2>&1; then
        fuser "${PORT}/tcp" > /dev/null 2>&1
    else
        return 1
    fi
}

# ── 杀掉旧进程 ────────────────────────────────────────────
echo "🔍 检查旧 next 进程..."
pkill -f "next start" 2>/dev/null || true

echo "🔍 检查端口 ${PORT} 占用..."
# 优先用 ss 找 PID（能看到 TIME_WAIT 等所有状态），再降级到 fuser/lsof
if command -v ss > /dev/null 2>&1; then
    SS_PIDS=$(ss -tlnp "sport = :${PORT}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u)
    if [ -n "${SS_PIDS}" ]; then
        echo "${SS_PIDS}" | xargs kill -9 2>/dev/null || true
    fi
fi
if command -v fuser > /dev/null 2>&1; then
    fuser -k "${PORT}/tcp" 2>/dev/null || true
elif command -v lsof > /dev/null 2>&1; then
    lsof -ti:"${PORT}" 2>/dev/null | xargs kill -9 2>/dev/null || true
fi

# ── 等待端口完全释放（最多 15 秒）────────────────────────
echo "⏳ 等待端口 ${PORT} 释放..."
for i in $(seq 1 15); do
    if ! port_in_use; then
        echo "   端口已释放 (${i}s)"
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "❌ 端口 ${PORT} 15 秒内未释放，放弃启动"
        exit 1
    fi
    sleep 1
done

# ── 启动服务 ──────────────────────────────────────────────
mkdir -p "${LOG_DIR}"

echo "🚀 后台启动生产服务器 (端口: ${PORT})..."
nohup npx pnpm start --hostname 0.0.0.0 --port "${PORT}" > "${LOG_DIR}/server.log" 2>&1 &
echo $! > .server.pid

echo "📝 进程 PID: $(cat .server.pid)"
