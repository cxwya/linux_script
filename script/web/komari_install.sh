#!/bin/bash
# Komari 探针部署脚本

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

echo "=== Komari 探针部署 ==="

# 1. 设置端口
read -p "请输入宿主机端口 (默认: 25774): " HOST_PORT </dev/tty
HOST_PORT=${HOST_PORT:-25774}

# 2. 设置数据目录
read -p "请输入数据存储目录 (默认: /data/komari/data): " HOST_DIR </dev/tty
HOST_DIR=${HOST_DIR:-/data/komari/data}

# 3. 设置容器名称
read -p "请输入容器名称 (默认: komari): " CONTAINER_NAME </dev/tty
CONTAINER_NAME=${CONTAINER_NAME:-komari}

# 4. 设置管理员账号
read -p "请输入管理员用户名 (留空自动生成): " ADMIN_USER </dev/tty
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
if [ -n "$ADMIN_USER" ]; then ENV_ARGS+=("-e" "ADMIN_USERNAME=$ADMIN_USER"); fi
if [ -n "$ADMIN_PASS" ]; then ENV_ARGS+=("-e" "ADMIN_PASSWORD=$ADMIN_PASS"); fi

# 启动容器
docker run -dit \
  -p "${HOST_PORT}:25774" \
  -v "${HOST_DIR}:/app/data" \
  --name "${CONTAINER_NAME}" \
  "${ENV_ARGS[@]}" \
  ghcr.io/komari-monitor/komari:latest

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

  # 获取/显示账号密码
  FINAL_USER="$ADMIN_USER"
  FINAL_PASS="$ADMIN_PASS"

  # 如果未设置账号或密码，尝试从日志获取
  if [ -z "$FINAL_USER" ] || [ -z "$FINAL_PASS" ]; then
    echo "正在等待容器初始化以获取默认账号密码 (约5秒)..."
    sleep 5
    LOGS=$(docker logs "$CONTAINER_NAME" 2>&1)
    # 日志格式: Default admin account created. Username: admin , Password: xxxxx
    if [ -z "$FINAL_USER" ]; then
      FINAL_USER=$(echo "$LOGS" | grep "Default admin account created" | sed -n 's/.*Username: \([^ ]*\) .*/\1/p')
    fi
    if [ -z "$FINAL_PASS" ]; then
      FINAL_PASS=$(echo "$LOGS" | grep "Default admin account created" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')
    fi
  fi

  echo "管理员用户: ${FINAL_USER:-admin (或查看日志)}"
  echo "管理员密码: ${FINAL_PASS:-请查看 docker logs $CONTAINER_NAME}"
  echo "======================"
else
  echo "部署失败，请检查报错信息。"
fi