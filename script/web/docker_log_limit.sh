#!/bin/bash
# Docker 日志限制配置脚本
# 支持交互输入日志驱动、单个日志文件大小、保留文件数量，并安全合并 daemon.json。

set -e

DAEMON_JSON="/etc/docker/daemon.json"
BACKUP_DIR="/etc/docker"

pause() {
  read -r -p "按回车继续..." </dev/tty
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行：sudo bash $0"
    exit 1
  fi
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "警告：未检测到 docker 命令。脚本仍可写入配置，但需要安装 Docker 后才会生效。"
    echo
  fi
}

prompt_driver() {
  while true; do
    echo "请选择 Docker 日志驱动："
    echo "  1) json-file 默认，兼容性好，限制日志大小也常用"
    echo "  2) local     Docker 官方推荐常规场景使用"
    read -r -p "请输入选项 [1]: " choice </dev/tty
    choice="${choice:-1}"

    case "$choice" in
      1)
        LOG_DRIVER="json-file"
        return
        ;;
      2)
        LOG_DRIVER="local"
        return
        ;;
      *)
        echo "无效选项，请输入 1 或 2。"
        echo
        ;;
    esac
  done
}

prompt_max_size() {
  while true; do
    read -r -p "请输入单个日志文件最大大小 [10m]: " value </dev/tty
    value="${value:-10m}"

    if echo "$value" | grep -Eq '^[1-9][0-9]*[kKmMgG]$'; then
      MAX_SIZE="$value"
      return
    fi

    echo "格式不正确。示例：5m、10m、100m、1g"
  done
}

prompt_max_file() {
  while true; do
    read -r -p "请输入每个容器保留的日志文件数量 [3]: " value </dev/tty
    value="${value:-3}"

    if echo "$value" | grep -Eq '^[1-9][0-9]*$'; then
      MAX_FILE="$value"
      return
    fi

    echo "格式不正确，请输入大于 0 的整数。"
  done
}

ensure_daemon_dir() {
  mkdir -p "$BACKUP_DIR"
}

backup_daemon_json() {
  if [ -f "$DAEMON_JSON" ]; then
    BACKUP_FILE="${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$DAEMON_JSON" "$BACKUP_FILE"
    echo "已备份原配置：$BACKUP_FILE"
  fi
}

write_with_python() {
  python3 - "$DAEMON_JSON" "$LOG_DRIVER" "$MAX_SIZE" "$MAX_FILE" <<'PY'
import json
import os
import sys

path, driver, max_size, max_file = sys.argv[1:5]

if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

if not isinstance(data, dict):
    raise SystemExit("daemon.json 顶层必须是 JSON 对象")

data["log-driver"] = driver
data["log-opts"] = {
    "max-size": max_size,
    "max-file": max_file,
}

tmp_path = path + ".tmp"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")

os.replace(tmp_path, path)
PY
}

write_with_jq() {
  local tmp_file
  tmp_file="$(mktemp)"

  if [ -f "$DAEMON_JSON" ] && [ -s "$DAEMON_JSON" ]; then
    jq \
      --arg driver "$LOG_DRIVER" \
      --arg max_size "$MAX_SIZE" \
      --arg max_file "$MAX_FILE" \
      '. + {"log-driver": $driver, "log-opts": {"max-size": $max_size, "max-file": $max_file}}' \
      "$DAEMON_JSON" > "$tmp_file"
  else
    jq -n \
      --arg driver "$LOG_DRIVER" \
      --arg max_size "$MAX_SIZE" \
      --arg max_file "$MAX_FILE" \
      '{"log-driver": $driver, "log-opts": {"max-size": $max_size, "max-file": $max_file}}' \
      > "$tmp_file"
  fi

  mv "$tmp_file" "$DAEMON_JSON"
}

write_simple_json() {
  cat > "$DAEMON_JSON" <<EOF
{
  "log-driver": "$LOG_DRIVER",
  "log-opts": {
    "max-size": "$MAX_SIZE",
    "max-file": "$MAX_FILE"
  }
}
EOF
}

write_config() {
  ensure_daemon_dir

  if [ -f "$DAEMON_JSON" ] && [ -s "$DAEMON_JSON" ]; then
    if command -v python3 >/dev/null 2>&1; then
      backup_daemon_json
      write_with_python
    elif command -v jq >/dev/null 2>&1; then
      backup_daemon_json
      write_with_jq
    else
      echo "检测到已有 $DAEMON_JSON，但系统没有 python3 或 jq，无法安全合并配置。"
      echo "为避免覆盖其它 Docker 配置，请先安装 python3 或 jq 后重试。"
      exit 1
    fi
  else
    backup_daemon_json
    write_simple_json
  fi

  echo
  echo "已写入 Docker 日志限制配置："
  cat "$DAEMON_JSON"
}

restart_docker() {
  echo
  read -r -p "是否现在重启 Docker 使配置生效？[y/N]: " answer </dev/tty
  case "$answer" in
    [Yy])
      if command -v systemctl >/dev/null 2>&1; then
        systemctl restart docker
      else
        service docker restart
      fi
      echo "Docker 已重启。"
      ;;
    *)
      echo "已跳过重启。请稍后手动执行：sudo systemctl restart docker"
      ;;
  esac
}

clean_old_json_logs() {
  echo
  echo "说明：新配置只会影响新创建的容器。已有容器通常需要重建后才会使用新的默认日志配置。"
  echo "如果之前使用 json-file，旧日志文件可能仍占用空间。"
  read -r -p "是否清空已有容器的 *-json.log 日志文件？[y/N]: " answer </dev/tty

  case "$answer" in
    [Yy])
      if [ ! -d /var/lib/docker/containers ]; then
        echo "未找到 /var/lib/docker/containers，跳过清理。"
        return
      fi
      find /var/lib/docker/containers -type f -name '*-json.log' -exec sh -c ': > "$1"' _ {} \;
      echo "已清空已有 json-file 容器日志。"
      ;;
    *)
      echo "已跳过旧日志清理。"
      ;;
  esac
}

show_summary() {
  echo
  echo "配置完成。当前限制："
  echo "  日志驱动：$LOG_DRIVER"
  echo "  单文件大小：$MAX_SIZE"
  echo "  保留文件数：$MAX_FILE"
  echo
  echo "如果使用 Docker Compose，已有服务建议重建："
  echo "  docker compose up -d --force-recreate"
}

main() {
  need_root
  check_docker

  echo "=============================="
  echo " Docker 日志限制配置"
  echo "=============================="
  echo

  prompt_driver
  prompt_max_size
  prompt_max_file
  write_config
  restart_docker
  clean_old_json_logs
  show_summary
  pause
}

main "$@"
