#!/bin/bash
# 进程守护脚本，由 crontab 定时调用
# 用法: PORT=10001 LOG_DIR=logs bash scripts/guard.sh

PORT="${PORT:-10001}"
LOG_DIR="${LOG_DIR:-logs}"

# 切换到项目根目录（脚本所在目录的上一级）
cd "$(dirname "$0")/.." || exit 1

MONITOR_LOG="${LOG_DIR}/monitor.log"
mkdir -p "${LOG_DIR}"

# 检查端口是否存活
if ! lsof -ti:"${PORT}" > /dev/null 2>&1; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") [ALERT] 端口 ${PORT} 无响应，尝试自动重启..." >> "${MONITOR_LOG}"

    # cron 环境 PATH 较窄，补充常见路径
    export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

    PORT="${PORT}" LOG_DIR="${LOG_DIR}" make start >> "${MONITOR_LOG}" 2>&1

    if lsof -ti:"${PORT}" > /dev/null 2>&1; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") [ OK ] 自动重启成功" >> "${MONITOR_LOG}"
    else
        echo "$(date "+%Y-%m-%d %H:%M:%S") [FAIL] 自动重启失败!" >> "${MONITOR_LOG}"
    fi
fi
