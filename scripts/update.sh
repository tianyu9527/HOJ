#!/bin/bash
# ============================================================
# HOJ 更新部署脚本（二开后使用）
# 使用方法: bash scripts/update.sh
#
# 工作流：
#   1. 本地修改代码 → git push 到你的 GitHub fork
#   2. 服务器执行此脚本 → 自动拉取、构建、部署
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 确保在项目根目录
cd "$(dirname "$0")/.."

echo -e "${BLUE}"
echo "============================================"
echo "   HOJ 更新部署"
echo "============================================"
echo -e "${NC}"

# ----------------------------------------------------------
# 1. 拉取最新代码
# ----------------------------------------------------------
log_info "拉取最新代码..."

# 保存本地修改（如果有）
if [ -n "$(git status --porcelain --exclude=.env --exclude=data/)" ]; then
    log_warn "检测到本地未提交的修改，正在暂存..."
    git stash
fi

# 拉取
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git pull origin "${BRANCH}"

log_info "代码已更新到最新 (${BRANCH})"

# ----------------------------------------------------------
# 2. 停止需要重建的服务
# ----------------------------------------------------------
log_info "停止业务服务..."
docker compose stop hoj-backend hoj-judgeserver hoj-web

# ----------------------------------------------------------
# 3. 重新构建并启动
# ----------------------------------------------------------
log_info "重新构建镜像..."

# 只重建有变化的服务
docker compose build --parallel hoj-backend hoj-judgeserver hoj-web

log_info "启动服务..."
docker compose up -d

# ----------------------------------------------------------
# 4. 等待服务就绪
# ----------------------------------------------------------
log_info "等待服务启动..."
sleep 30

# ----------------------------------------------------------
# 5. 健康检查
# ----------------------------------------------------------
log_info "执行健康检查..."
echo ""
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""

# 检查各服务
ALL_OK=true

if docker compose ps hoj-mysql | grep -q "running"; then
    log_info "✅ MySQL     正常"
else
    log_error "❌ MySQL     异常"
    ALL_OK=false
fi

if docker compose ps hoj-redis | grep -q "running"; then
    log_info "✅ Redis     正常"
else
    log_error "❌ Redis     异常"
    ALL_OK=false
fi

if docker compose ps hoj-nacos | grep -q "running"; then
    log_info "✅ Nacos     正常"
else
    log_error "❌ Nacos     异常"
    ALL_OK=false
fi

if docker compose ps hoj-backend | grep -q "running"; then
    log_info "✅ Backend   正常"
else
    log_error "❌ Backend   异常"
    ALL_OK=false
fi

if docker compose ps hoj-judgeserver | grep -q "running"; then
    log_info "✅ Judge     正常"
else
    log_error "❌ Judge     异常"
    ALL_OK=false
fi

if docker compose ps hoj-web | grep -q "running"; then
    log_info "✅ Frontend  正常"
else
    log_error "❌ Frontend  异常"
    ALL_OK=false
fi

echo ""
if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   ✅ 更新部署成功！${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}   ⚠️  部分服务异常，请查看日志：${NC}"
    echo -e "${RED}   docker compose logs [服务名]${NC}"
    echo -e "${RED}============================================${NC}"
fi

# 清理旧镜像
docker image prune -f 2>/dev/null || true

echo ""
log_info "如需查看实时日志: docker compose logs -f"
