#!/bin/bash
# ==============================================
# 部署脚本 for IDX / VPS - 纯 LF 格式
# 支持自动安装依赖、环境检测、错误退出
# ==============================================

set -e  # 出错立即退出
set -u  # 使用未定义变量时退出
set -o pipefail

# ======= 基础信息 =======
APP_NAME="CloudProxy"
INSTALL_DIR="$HOME/${APP_NAME}"
PORT=2546   # 固定端口，持久化
REPO_URL="https://raw.githubusercontent.com/ka234ka/idx-suoha/main"

# ======= 检查并安装依赖 =======
echo "[1/5] 检查并安装依赖..."
PKGS=(curl wget unzip tar)
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y "${PKGS[@]}"
elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "${PKGS[@]}"
else
    echo "❌ 不支持的包管理器，请手动安装依赖: ${PKGS[*]}"
    exit 1
fi

# ======= 创建目录 =======
echo "[2/5] 创建部署目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# ======= 下载最新可执行文件或配置 =======
echo "[3/5] 下载部署文件..."
curl -fsSL "$REPO_URL/config.json" -o "$INSTALL_DIR/config.json"

# ======= 启动服务（示例命令，可替换） =======
echo "[4/5] 启动服务..."
# 假设服务程序名为 cloudproxy
if [ -f "$INSTALL_DIR/cloudproxy" ]; then
    chmod +x "$INSTALL_DIR/cloudproxy"
    "$INSTALL_DIR/cloudproxy" --config "$INSTALL_DIR/config.json" --port $PORT &
else
    echo "⚠️ 未检测到可执行文件，请确认 $INSTALL_DIR 下存在 cloudproxy"
fi

# ======= 健康检查 =======
echo "[5/5] 健康检查..."
sleep 2
if lsof -i :$PORT >/dev/null 2>&1; then
    echo "✅ 服务已在端口 $PORT 运行"
else
    echo "❌ 服务启动失败，请检查日志"
fi

echo "🎯 部署完成"



