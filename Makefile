# ============================================================
# JSONL Viewer - Makefile
# 快速开发、调试、构建和部署工具
# ============================================================

.PHONY: help install dev build start stop status monitor unmonitor lint clean \
        docker-build docker-run docker-stop docker-push docker-clean \
        check deps-update type-check

# 默认目标
.DEFAULT_GOAL := help

# 可配置变量
PORT              ?= 10001         # 服务端口
NODE_ENV          ?= development   # Node 环境
IMAGE_NAME        ?= jsonl-viewer  # Docker 镜像名
IMAGE_TAG         ?= latest        # Docker 镜像标签
CONTAINER         ?= jsonl-viewer  # Docker 容器名
LOG_DIR           ?= logs           # 日志目录
MONITOR_INTERVAL  ?= 1              # 守护检查间隔（分钟）
PNPM              := npx pnpm      # pnpm 命令

## ==================== 帮助 ====================
help: ## 显示帮助信息
	@echo "JSONL Viewer - Makefile 命令列表"
	@echo "============================================================"
	@echo ""
	@echo "开发调试:"
	@echo "  make install        - 安装项目依赖"
	@echo "  make dev            - 启动开发服务器 (默认端口 $(PORT))"
	@echo "  make build          - 构建生产版本"
	@echo "  make start          - 后台启动生产服务器 (nohup, 默认端口 $(PORT))"
	@echo "  make stop           - 停止本地生产服务器"
	@echo "  make status         - 查看服务运行状态"
	@echo "  make monitor        - 启动定时守护 (每 $(MONITOR_INTERVAL) 分钟检查存活并自动重启)"
	@echo "  make unmonitor      - 关闭定时守护"
	@echo "  make lint           - 运行代码检查"
	@echo "  make type-check     - TypeScript 类型检查"
	@echo "  make clean          - 清理构建产物"
	@echo ""
	@echo "Docker 部署:"
	@echo "  make docker-build   - 构建 Docker 镜像"
	@echo "  make docker-run     - 运行 Docker 容器 (端口: $(PORT))"
	@echo "  make docker-stop    - 停止 Docker 容器"
	@echo "  make docker-push    - 推送 Docker 镜像到仓库"
	@echo "  make docker-clean   - 清理 Docker 镜像和容器"
	@echo ""
	@echo "检查工具:"
	@echo "  make check          - 运行所有检查 (lint + type-check)"
	@echo "  make deps-update    - 更新依赖到最新版本"
	@echo ""
	@echo "可配置环境变量:"
@echo "  PORT       - 服务端口 (默认: 10001)"
	@echo "  IMAGE_NAME - Docker 镜像名 (默认: jsonl-viewer)"
	@echo "  IMAGE_TAG  - Docker 镜像标签 (默认: latest)"
	@echo "  CONTAINER  - Docker 容器名 (默认: jsonl-viewer)"
	@echo ""
	@echo "示例:"
	@echo "  make dev PORT=8080          - 在 8080 端口启动开发服务器"
	@echo "  make docker-run PORT=8080   - 在 8080 端口运行容器"
	@echo "  make docker-build IMAGE_TAG=v1.2.0"

## ==================== 开发调试 ====================
install: ## 安装项目依赖
	@echo "📦 安装依赖..."
	$(PNPM) install

dev: ## 启动开发服务器 (支持热重载)
	@echo "🔍 检查旧 next 进程..."
	@pkill -f "next dev" 2>/dev/null || true
	@echo "🔍 检查端口 $(PORT) 占用..."
	@lsof -ti:$(PORT) 2>/dev/null | xargs kill -9 2>/dev/null || true
	@sleep 1
	@echo "🚀 启动开发服务器 (端口: $(PORT))..."
	$(PNPM) dev --port $(PORT)

build: ## 构建生产版本
	@echo "🔨 构建生产版本..."
	NODE_ENV=production $(PNPM) build

start: build ## 构建并后台启动生产服务器 (nohup 模式)
	@PORT=$(PORT) LOG_DIR=$(LOG_DIR) bash scripts/start.sh
	@sleep 4
	@echo ""
	@echo "========================================" 
	@if lsof -ti:$(PORT) > /dev/null 2>&1; then \
		echo " ✅ 服务启动成功!"; \
		echo ""; \
		echo " 📍 本地访问: http://localhost:$(PORT)"; \
		LOCAL_IP=$$(hostname -I 2>/dev/null | awk '{print $$1}' || echo ""); \
		if [ -n "$$LOCAL_IP" ]; then \
			echo " 📍 内网访问: http://$$LOCAL_IP:$(PORT)"; \
		fi; \
		echo ""; \
		echo " 📋 查看日志: tail -f $(LOG_DIR)/server.log"; \
		echo " 📊 查看状态: make status"; \
		echo " 🛑 停止服务: make stop"; \
	else \
		echo " ❌ 启动失败，请查看日志: $(LOG_DIR)/server.log"; \
		exit 1; \
	fi
	@echo "========================================"
stop: ## 停止本地生产服务器
	@echo "🛑 停止生产服务器..."
	@pkill -f "next start" 2>/dev/null || true
	@if [ -f .server.pid ]; then \
		kill $$(cat .server.pid) 2>/dev/null || true; \
		rm -f .server.pid; \
	fi
	@echo "✅ 已停止"

status: ## 查看服务运行状态
	@echo "📊 服务状态检查..."
	@echo "----------------------------------------"
	@PID=$$(lsof -ti:$(PORT) 2>/dev/null || true); \
	if [ -n "$$PID" ]; then \
		echo "状态: 🟢 运行中"; \
		echo "端口: $(PORT)"; \
		echo "PID : $$PID"; \
		echo "URL : http://localhost:$(PORT)"; \
		echo "----------------------------------------"; \
		if command -v curl > /dev/null 2>&1; then \
			STATUS=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$(PORT) 2>/dev/null || echo "000"); \
			echo "HTTP: $$STATUS"; \
		fi; \
	else \
		echo "状态: 🔴 未运行"; \
	fi

monitor: ## 启动定时守护（定时检查存活并自动重启）
	@echo "🔧 安装定时守护 (每 $(MONITOR_INTERVAL) 分钟检查一次)..."
	@(crontab -l 2>/dev/null | grep -v "scripts/guard.sh"; \
	  echo "*/$(MONITOR_INTERVAL) * * * * /bin/bash $(PWD)/scripts/guard.sh") | crontab -
	@echo "✅ 定时守护已启动!"
	@echo "   检查间隔: 每 $(MONITOR_INTERVAL) 分钟"
	@echo "   守护日志: tail -f $(LOG_DIR)/monitor.log"
	@echo "   关闭守护: make unmonitor"

unmonitor: ## 关闭定时守护
	@echo "🛑 移除定时守护..."
	@crontab -l 2>/dev/null | grep -v "scripts/guard.sh" | crontab - || true
	@echo "✅ 定时守护已关闭"

lint: ## 运行 ESLint 代码检查
	@echo "🔍 运行代码检查..."
	$(PNPM) lint

type-check: ## TypeScript 类型检查
	@echo "🔍 TypeScript 类型检查..."
	$(PNPM) exec tsc --noEmit

check: lint type-check ## 运行所有检查

deps-update: ## 更新依赖到最新版本
	@echo "🔄 更新依赖..."
	$(PNPM) update --latest

clean: ## 清理构建产物和缓存
	@echo "🧹 清理构建产物..."
	rm -rf .next out build
	rm -rf public/sw.js public/workbox-*.js
	rm -rf $(LOG_DIR)
	rm -f .server.pid
	@echo "✅ 清理完成"

## ==================== Docker 部署 ====================
docker-build: ## 构建 Docker 镜像
	@echo "🐳 构建 Docker 镜像: $(IMAGE_NAME):$(IMAGE_TAG)..."
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

docker-run: ## 运行 Docker 容器（后台运行，端口可配置）
	@echo "🐳 启动容器: $(CONTAINER) (端口: $(PORT):$(PORT))..."
	@docker rm -f $(CONTAINER) 2>/dev/null || true
	docker run -d \
		--name $(CONTAINER) \
		-p $(PORT):$(PORT) \
		-e PORT=$(PORT) \
		-e NODE_ENV=production \
		--restart unless-stopped \
		$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "✅ 容器已启动: http://localhost:$(PORT)"

docker-stop: ## 停止并删除 Docker 容器
	@echo "🛑 停止容器: $(CONTAINER)..."
	docker stop $(CONTAINER) 2>/dev/null || true
	docker rm $(CONTAINER) 2>/dev/null || true
	@echo "✅ 容器已停止"

docker-push: ## 推送 Docker 镜像到仓库
	@echo "📤 推送镜像: $(IMAGE_NAME):$(IMAGE_TAG)..."
	docker push $(IMAGE_NAME):$(IMAGE_TAG)

docker-clean: docker-stop ## 清理 Docker 镜像和容器
	@echo "🧹 清理 Docker 资源..."
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	docker image prune -f
	@echo "✅ Docker 清理完成"
