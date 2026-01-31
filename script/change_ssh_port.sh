#!/bin/bash
# 一键修改 SSH 端口脚本
# 使用方式：
#   交互式：sudo bash change_ssh_port.sh
#   指定端口：sudo bash change_ssh_port.sh 2222

set -e

SSHD_CONFIG="/etc/ssh/sshd_config"

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本（例如：sudo $0）"
  exit 1
fi

# 检查 sshd_config 是否存在
if [ ! -f "$SSHD_CONFIG" ]; then
  echo "未找到 $SSHD_CONFIG，当前系统可能未安装 OpenSSH 服务器。"
  exit 1
fi

# 检查端口是否空闲
check_port_free() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -qE "[.:]${port}[[:space:]]"; then
      echo "端口 $port 已被占用！"
      return 1
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -qE "[.:]${port}[[:space:]]"; then
      echo "端口 $port 已被占用！"
      return 1
    fi
  fi

  return 0
}

# 获取合法且未占用的端口
get_valid_port() {
  local port
  local first_arg="$1"

  while true; do
    echo "======================"
    if [ -n "$first_arg" ]; then
      port="$first_arg"
      first_arg=""      # 只使用一次命令行参数，后续改为手动输入
      echo "使用命令行传入端口：$port"
    else
      read -p "请输入要修改成的 SSH 端口（例如 2222）: " port </dev/tty
    fi

    echo "你刚输入的端口是：$port"

    # 1. 数字检查
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      echo "端口必须为数字，请重新输入。"
      continue
    fi

    # 2. 范围检查：22 或 1024–65535
    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ] ; then
      echo "端口必须1-65535 之间，请重新输入。"
      continue
    fi

    # 3. 占用检查（输入后立刻检查并提示）
    if ! check_port_free "$port"; then
      echo "请重新输入一个未被占用的端口。"
      continue
    fi

    # 4. 所有检查通过
    echo "端口合法且未被占用，使用端口：$port"
    NEW_PORT="$port"
    return 0
  done
}

echo "=== SSH 端口修改脚本 ==="
echo "1) 修改端口"
echo "0) 退出"
echo "======================"
read -p "请选择 (0/1): " start_choice </dev/tty

if [ "$start_choice" = "0" ]; then
  echo "已退出。"
  exit 0
fi

# 获取目标端口（优先使用命令行参数）
get_valid_port "$1"
echo "准备将 SSH 端口修改为: $NEW_PORT"

# 备份配置
BACKUP_FILE="${SSHD_CONFIG}.$(date +%F_%H%M%S).bak"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
echo "已备份当前配置到: $BACKUP_FILE"

# 修改 sshd_config 中的端口：
# 1. 如果有以 Port 开头的行，直接替换
# 2. 如果只有 #Port 22 注释行，则取消注释并修改
# 3. 如果都没有，则追加一行 Port NEW_PORT
if grep -qE '^[[:space:]]*Port[[:space:]]+' "$SSHD_CONFIG"; then
  sed -i -E "s/^[[:space:]]*Port[[:space:]]+.*/Port $NEW_PORT/" "$SSHD_CONFIG"
elif grep -qE '^[[:space:]]*#?[[:space:]]*Port[[:space:]]+22' "$SSHD_CONFIG"; then
  sed -i -E "s/^[[:space:]]*#?[[:space:]]*Port[[:space:]]+22/Port $NEW_PORT/" "$SSHD_CONFIG"
else
  echo "Port $NEW_PORT" >> "$SSHD_CONFIG"
fi

echo "已写入新端口配置到 $SSHD_CONFIG"

# 测试配置（部分系统支持 sshd -t）
if command -v sshd >/dev/null 2>&1; then
  if sshd -t 2>/tmp/sshd_check.err; then
    echo "sshd 配置检查通过。"
  else
    echo "sshd 配置检查失败，恢复备份..."
    cat /tmp/sshd_check.err
    mv "$BACKUP_FILE" "$SSHD_CONFIG"
    exit 1
  fi
fi

# 防火墙放行新端口（按需保留或注释）
if command -v firewall-cmd >/dev/null 2>&1; then
  echo "检测到 firewalld，尝试放行端口 $NEW_PORT/tcp ..."
  firewall-cmd --permanent --add-port="${NEW_PORT}"/tcp || true
  firewall-cmd --reload || true
fi

if command -v ufw >/dev/null 2>&1; then
  echo "检测到 ufw，尝试放行端口 $NEW_PORT/tcp ..."
  ufw allow "$NEW_PORT"/tcp || true
fi

# 重启 SSH 服务，兼容 sshd / ssh 名称及非 systemd 系统
SERVICE_NAME=""
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q '^sshd.service'; then
    SERVICE_NAME="sshd"
  elif systemctl list-unit-files | grep -q '^ssh.service'; then
    SERVICE_NAME="ssh"
  fi

  if [ -n "$SERVICE_NAME" ]; then
    echo "重启 $SERVICE_NAME 服务以应用新端口..."
    systemctl restart "$SERVICE_NAME"
  else
    echo "未检测到 systemd ssh 服务，尝试使用 service sshd/ssh restart ..."
    if command -v service >/dev/null 2>&1; then
      service sshd restart || service ssh restart || true
    fi
  fi
else
  if command -v service >/dev/null 2>&1; then
    echo "使用 service 重启 SSH 服务..."
    service sshd restart || service ssh restart || true
  else
    echo "未找到合适的方式自动重启 SSH 服务，请手动重启 SSH。"
  fi
fi

echo
echo "=== SSH 端口已修改为: $NEW_PORT ==="
echo "请不要立即断开当前会话。"
echo "先新开一个终端测试新端口是否可用，例如："
echo "  ssh -p $NEW_PORT 用户名@服务器IP"
echo "确认可以登录后，再关闭当前连接。"
