#!/bin/bash
# 文件夹备份脚本
# 功能：备份指定目录、自定义存储位置、自动压缩、HTTP下载

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行：sudo $0"
  exit 1
fi

install_pv() {
  if command -v pv >/dev/null 2>&1; then
    return 0
  fi

  echo "未检测到 pv，正在自动安装进度条工具..."

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y pv
  elif command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt update && apt install -y pv
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y pv
  elif command -v yum >/dev/null 2>&1; then
    yum install -y pv
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache pv
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm pv
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install pv
  else
    echo "未找到支持的包管理器，跳过自动安装 pv。"
    return 1
  fi

  if command -v pv >/dev/null 2>&1; then
    echo "pv 安装成功。"
    return 0
  fi

  echo "pv 自动安装失败，将使用普通压缩模式。"
  return 1
}

echo "=== 文件夹备份 ==="

# 1. 输入源目录
while true; do
  read -p "请输入要备份的文件夹路径 (例如 /www/wwwroot/site): " SOURCE_DIR </dev/tty
  if [ -d "$SOURCE_DIR" ]; then
    # 去除末尾的 /
    SOURCE_DIR=${SOURCE_DIR%/}
    break
  else
    echo "错误：目录不存在，请重新输入。"
  fi
done

# 2. 输入备份保存目录
read -p "请输入备份存放目录 (默认: /root/backup): " BACKUP_DIR </dev/tty
BACKUP_DIR=${BACKUP_DIR:-/root/backup}
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  echo "已创建目录: $BACKUP_DIR"
fi

# 3. 生成文件名
DATE=$(date +%Y%m%d_%H%M%S)
RAND_STR=$(tr -dc 'a-zA-Z' < /dev/urandom | head -c 6)

# 格式化路径：去掉开头的 /，将 / 替换为 -
SANITIZED_PATH=$(echo "$SOURCE_DIR" | sed 's|^/||; s|/|-|g')
DIR_NAME=$(basename "$SOURCE_DIR")

# 格式: path_源文件夹路径_名称_时间_随机6位字母.tar.gz
FILENAME="path_${SANITIZED_PATH}_${DIR_NAME}_${DATE}_${RAND_STR}.tar.gz"
FILE_PATH="$BACKUP_DIR/$FILENAME"

echo "正在压缩..."
echo "源目录: $SOURCE_DIR"
echo "目标文件: $FILE_PATH"

# tar 压缩
# -C 切换到父目录，然后压缩目录名，防止压缩包内包含绝对路径结构
PARENT_DIR=$(dirname "$SOURCE_DIR")

if ! command -v pv >/dev/null 2>&1; then
  install_pv
fi

if command -v pv >/dev/null 2>&1; then
  echo "正在计算进度条总量..."
  TAR_STREAM_SIZE=$(tar -cf - -C "$PARENT_DIR" "$DIR_NAME" 2>/dev/null | wc -c | awk '{print $1}')
else
  TAR_STREAM_SIZE=""
fi

if command -v pv >/dev/null 2>&1 && [ -n "$TAR_STREAM_SIZE" ] && [ "$TAR_STREAM_SIZE" -gt 0 ] 2>/dev/null; then
  echo "正在生成压缩包，进度如下："
  set -o pipefail
  tar -cf - -C "$PARENT_DIR" "$DIR_NAME" | pv -pterb -s "$TAR_STREAM_SIZE" | gzip > "$FILE_PATH"
  TAR_STATUS=$?
  set +o pipefail
else
  if ! command -v pv >/dev/null 2>&1; then
    echo "提示：未检测到 pv 或自动安装失败，使用普通压缩模式。"
  fi
  tar -czf "$FILE_PATH" -C "$PARENT_DIR" "$DIR_NAME"
  TAR_STATUS=$?
fi

if [ "$TAR_STATUS" -eq 0 ] && [ -s "$FILE_PATH" ]; then
  echo "✓ 备份成功！"
  echo "文件大小: $(du -h "$FILE_PATH" | awk '{print $1}')"
  
  echo "----------------------"
  echo "请选择获取备份文件的方式："
  echo "  1) 开启临时 HTTP 端口 (直接下载)"
  echo "  0) 仅保留本地文件"
  read -p "请选择 (0-1): " dl_choice </dev/tty
  
  case "$dl_choice" in
    1)
      read -p "请输入开放端口 (默认 8000): " HTTP_PORT </dev/tty
      HTTP_PORT=${HTTP_PORT:-8000}
      
      # 自动开放防火墙端口
      FIREWALL_TYPE=""
      if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        if ufw allow "$HTTP_PORT"/tcp >/dev/null 2>&1; then
          FIREWALL_TYPE="ufw"
          echo "已通过 UFW 开放端口 $HTTP_PORT"
        else
          echo "警告：UFW 端口开放失败，请手动检查。"
        fi
      elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        if firewall-cmd --zone=public --add-port="$HTTP_PORT"/tcp --permanent >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1; then
          FIREWALL_TYPE="firewalld"
          echo "已通过 FirewallD 开放端口 $HTTP_PORT"
        else
          echo "警告：FirewallD 端口开放失败，请手动检查。"
        fi
      elif command -v iptables >/dev/null 2>&1; then
        if iptables -I INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT >/dev/null 2>&1; then
          FIREWALL_TYPE="iptables"
          echo "已通过 iptables 开放端口 $HTTP_PORT (临时)"
        else
          echo "警告：iptables 端口开放失败，请手动检查。"
        fi
      fi
      
      # 获取 IP
      IPV4=$(curl -s -4 --connect-timeout 2 ifconfig.me 2>/dev/null)
      [ -z "$IPV4" ] && IPV4=$(hostname -I | awk '{print $1}')
      
      echo "======================"
      echo "正在启动临时 HTTP 服务..."
      echo "下载地址: http://${IPV4}:${HTTP_PORT}/$FILENAME"
      echo "提示：请确保防火墙已放行该端口。"
      echo "======================"
      
      cd "$BACKUP_DIR" || exit
      
      if command -v python3 >/dev/null 2>&1; then
        nohup python3 -m http.server "$HTTP_PORT" >/dev/null 2>&1 &
        PID=$!
      elif command -v python >/dev/null 2>&1; then
        nohup python -m SimpleHTTPServer "$HTTP_PORT" >/dev/null 2>&1 &
        PID=$!
      else
        echo "错误：未检测到 Python 环境，无法启动 HTTP 服务。"
        echo "文件路径: $FILE_PATH"
        PID=""
      fi
      
      if [ -n "$PID" ]; then
        echo "HTTP 服务已在后台运行 (PID: $PID)。"
        echo "您可以断开 SSH 连接，服务不会中断。"
        echo "下载完成后，请按顺序运行以下命令停止服务并清理端口："
        echo "  kill $PID"
        case "$FIREWALL_TYPE" in
          ufw)
            echo "  ufw --force delete allow ${HTTP_PORT}/tcp"
            ;;
          firewalld)
            echo "  firewall-cmd --zone=public --remove-port=${HTTP_PORT}/tcp --permanent"
            echo "  firewall-cmd --reload"
            ;;
          iptables)
            echo "  iptables -D INPUT -p tcp --dport $HTTP_PORT -j ACCEPT"
            ;;
          *)
            echo "  # 如手动放行过端口，请手动关闭 ${HTTP_PORT}/tcp"
            ;;
        esac
      fi
      ;;
    *)
      echo "======================"
      echo "备份结束。"
      echo "文件路径: $FILE_PATH"
      echo "======================"
      ;;
  esac

else
  echo "✗ 备份失败！"
  rm -f "$FILE_PATH"
fi
