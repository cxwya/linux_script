#!/bin/bash
# OpenList 部署脚本

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行：sudo $0"
  exit 1
fi

# 检查 Docker 是否安装
if ! command -v docker >/dev/null 2>&1; then
  echo "错误：未检测到 Docker，请先安装 Docker。"
  exit 1
fi

echo "=== OpenList 部署 ==="

# 1. 设置端口
read -p "请输入宿主机端口 (默认: 5244): " HOST_PORT </dev/tty
HOST_PORT=${HOST_PORT:-5244}

# 2. 设置数据目录
read -p "请输入数据存储目录 (默认: /data/openlist/data): " HOST_DIR </dev/tty
HOST_DIR=${HOST_DIR:-/data/openlist/data}

# 3. 设置容器名称
read -p "请输入容器名称 (默认: openlist): " CONTAINER_NAME </dev/tty
CONTAINER_NAME=${CONTAINER_NAME:-openlist}

# 4. 设置管理员密码
read -p "请输入管理员密码 (留空自动生成): " ADMIN_PASS </dev/tty

# 创建目录
if [ ! -d "$HOST_DIR" ]; then
  echo "创建目录: $HOST_DIR"
  mkdir -p "$HOST_DIR"
fi

# 检查容器名是否冲突
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "警告：容器名称 $CONTAINER_NAME 已存在。"
  read -p "是否删除旧容器并重新部署？(y/n): " confirm </dev/tty
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
    echo "旧容器已删除。"
  else
    echo "部署取消。"
    exit 0
  fi
fi

echo "正在拉取镜像并启动容器..."

# 构造环境变量参数
ENV_ARGS=()
if [ -n "$ADMIN_PASS" ]; then ENV_ARGS+=("-e" "OPENLIST_ADMIN_PASSWORD=$ADMIN_PASS"); fi

# 启动容器
docker run -d \
  --restart=unless-stopped \
  -p "${HOST_PORT}:5244" \
  -v "${HOST_DIR}:/opt/openlist/data" \
  --user "$(id -u):$(id -g)" \
  --name "${CONTAINER_NAME}" \
  "${ENV_ARGS[@]}" \
  openlistteam/openlist:latest

if [ $? -eq 0 ]; then
  echo "======================"
  echo "部署成功！"
  echo "容器名称: $CONTAINER_NAME"
  
  # 获取 IPv4 (优先公网)
  IPV4=$(curl -s -4 --connect-timeout 2 ifconfig.me 2>/dev/null)
  [ -z "$IPV4" ] && IPV4=$(hostname -I | awk '{print $1}')
  [ -n "$IPV4" ] && echo "IPv4 访问地址: http://${IPV4}:${HOST_PORT}"

  # 获取 IPv6 (优先公网)
  IPV6=$(curl -s -6 --connect-timeout 2 ifconfig.me 2>/dev/null)
  [ -z "$IPV6" ] && IPV6=$(ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
  [ -n "$IPV6" ] && echo "IPv6 访问地址: http://[${IPV6}]:${HOST_PORT}"

  echo "数据目录: $HOST_DIR"

  # 获取/显示密码
  FINAL_PASS="$ADMIN_PASS"
  if [ -z "$FINAL_PASS" ]; then
    echo "正在等待容器初始化以获取默认密码 (约5秒)..."
    sleep 5
    LOGS=$(docker logs "$CONTAINER_NAME" 2>&1)
    # 日志格式: Successfully created the admin user and the initial password is: xYZabHGf
    FINAL_PASS=$(echo "$LOGS" | grep "initial password is:" | sed -n 's/.*initial password is: \([^ ]*\).*/\1/p')
  fi

  echo "默认账号: admin"
  echo "管理员密码: ${FINAL_PASS:-请查看 docker logs $CONTAINER_NAME}"
  echo "======================"
else
  echo "部署失败，请检查报错信息。"
fi
