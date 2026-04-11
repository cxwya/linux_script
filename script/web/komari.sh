#!/bin/bash
# Komari 管理脚本（安装 + 更新）

IMAGE="ghcr.io/komari-monitor/komari:latest"
DEFAULT_CONTAINER_NAME="komari"
DEFAULT_HOST_PORT="25774"
DEFAULT_HOST_DIR="/data/komari/data"
CONTAINER_PORT="25774"
CONTAINER_DATA_DIR="/app/data"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行：sudo $0"
    exit 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "错误：未检测到 Docker，请先安装 Docker。"
    exit 1
  fi
}

short_id() {
  local full_id="$1"
  if [ -z "$full_id" ]; then
    echo "N/A"
    return
  fi
  echo "${full_id#sha256:}" | cut -c1-12
}

validate_port() {
  local port="$1"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    return 1
  fi
  return 0
}

container_exists() {
  local container_name="$1"
  docker ps -a --format '{{.Names}}' | grep -Fxq "$container_name"
}

get_container_host_port() {
  local container_name="$1"
  docker inspect \
    --format '{{with (index .NetworkSettings.Ports "25774/tcp")}}{{(index . 0).HostPort}}{{end}}' \
    "$container_name" 2>/dev/null
}

get_container_host_dir() {
  local container_name="$1"
  docker inspect \
    --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}' \
    "$container_name" 2>/dev/null
}

get_container_image_id() {
  local container_name="$1"
  docker inspect --format '{{.Image}}' "$container_name" 2>/dev/null
}

get_image_id() {
  docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null
}

get_image_created() {
  docker image inspect --format '{{.Created}}' "$IMAGE" 2>/dev/null
}

get_image_digest() {
  docker image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}未记录摘要{{end}}' "$IMAGE" 2>/dev/null
}

print_access_info() {
  local host_port="$1"
  local host_dir="$2"
  local container_name="$3"

  echo "容器名称: $container_name"

  local ipv4
  ipv4=$(curl -s -4 --connect-timeout 2 ifconfig.me 2>/dev/null)
  [ -z "$ipv4" ] && ipv4=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -n "$ipv4" ] && echo "IPv4 访问地址: http://${ipv4}:${host_port}"

  local ipv6
  ipv6=$(curl -s -6 --connect-timeout 2 ifconfig.me 2>/dev/null)
  [ -z "$ipv6" ] && ipv6=$(ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
  [ -n "$ipv6" ] && echo "IPv6 访问地址: http://[${ipv6}]:${host_port}"

  echo "数据目录: $host_dir"
}

run_container() {
  local container_name="$1"
  local host_port="$2"
  local host_dir="$3"
  local admin_user="$4"
  local admin_pass="$5"

  local env_args=()
  if [ -n "$admin_user" ]; then
    env_args+=("-e" "ADMIN_USERNAME=$admin_user")
  fi
  if [ -n "$admin_pass" ]; then
    env_args+=("-e" "ADMIN_PASSWORD=$admin_pass")
  fi

  docker run -d \
    -p "${host_port}:${CONTAINER_PORT}" \
    -v "${host_dir}:${CONTAINER_DATA_DIR}" \
    --name "${container_name}" \
    "${env_args[@]}" \
    "$IMAGE"
}

install_komari() {
  echo "=== Komari 安装 ==="

  read -p "请输入宿主机端口 (默认: ${DEFAULT_HOST_PORT}): " host_port </dev/tty
  host_port=${host_port:-$DEFAULT_HOST_PORT}
  if ! validate_port "$host_port"; then
    echo "错误：端口无效（范围 1-65535）。"
    return 1
  fi

  read -p "请输入数据存储目录 (默认: ${DEFAULT_HOST_DIR}): " host_dir </dev/tty
  host_dir=${host_dir:-$DEFAULT_HOST_DIR}
  if [ -z "$host_dir" ]; then
    echo "错误：数据目录不能为空。"
    return 1
  fi

  read -p "请输入容器名称 (默认: ${DEFAULT_CONTAINER_NAME}): " container_name </dev/tty
  container_name=${container_name:-$DEFAULT_CONTAINER_NAME}

  read -p "请输入管理员用户名 (留空自动生成): " admin_user </dev/tty
  read -p "请输入管理员密码 (留空自动生成): " admin_pass </dev/tty

  if [ ! -d "$host_dir" ]; then
    echo "创建目录: $host_dir"
    mkdir -p "$host_dir" || {
      echo "错误：目录创建失败。"
      return 1
    }
  fi

  if container_exists "$container_name"; then
    echo "警告：容器名称 $container_name 已存在。"
    read -p "是否删除旧容器并重新部署？(y/n): " confirm </dev/tty
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
      docker stop "$container_name" >/dev/null 2>&1 || true
      docker rm "$container_name" >/dev/null 2>&1 || true
      echo "旧容器已删除。"
    else
      echo "安装已取消。"
      return 0
    fi
  fi

  echo "正在拉取镜像..."
  if ! docker pull "$IMAGE"; then
    echo "错误：拉取镜像失败。"
    return 1
  fi

  echo "正在启动容器..."
  if run_container "$container_name" "$host_port" "$host_dir" "$admin_user" "$admin_pass"; then
    echo "======================"
    echo "安装成功！"
    print_access_info "$host_port" "$host_dir" "$container_name"

    local final_user="$admin_user"
    local final_pass="$admin_pass"
    if [ -z "$final_user" ] || [ -z "$final_pass" ]; then
      echo "正在等待容器初始化以获取默认账号密码 (约5秒)..."
      sleep 5
      local logs
      logs=$(docker logs "$container_name" 2>&1)
      if [ -z "$final_user" ]; then
        final_user=$(echo "$logs" | grep "Default admin account created" | sed -n 's/.*Username: \([^ ]*\) .*/\1/p')
      fi
      if [ -z "$final_pass" ]; then
        final_pass=$(echo "$logs" | grep "Default admin account created" | sed -n 's/.*Password: \([^ ]*\).*/\1/p')
      fi
    fi

    echo "管理员用户: ${final_user:-admin (或查看日志)}"
    echo "管理员密码: ${final_pass:-请查看 docker logs $container_name}"
    echo "======================"
    return 0
  fi

  echo "安装失败，请检查报错信息。"
  return 1
}

update_komari() {
  echo "=== Komari 更新 ==="

  read -p "请输入要更新的容器名称 (默认: ${DEFAULT_CONTAINER_NAME}): " container_name </dev/tty
  container_name=${container_name:-$DEFAULT_CONTAINER_NAME}

  local default_port="$DEFAULT_HOST_PORT"
  local default_dir="$DEFAULT_HOST_DIR"
  local current_container_image_id=""
  local exists=0

  if container_exists "$container_name"; then
    exists=1
    current_container_image_id=$(get_container_image_id "$container_name")
    local detected_port
    detected_port=$(get_container_host_port "$container_name")
    if validate_port "$detected_port"; then
      default_port="$detected_port"
    fi
    local detected_dir
    detected_dir=$(get_container_host_dir "$container_name")
    [ -n "$detected_dir" ] && default_dir="$detected_dir"
  fi

  local local_image_id_before
  local local_image_created_before
  local local_image_digest_before
  local_image_id_before=$(get_image_id)
  local_image_created_before=$(get_image_created)
  local_image_digest_before=$(get_image_digest)

  echo "正在检查远程最新版本..."
  if ! docker pull "$IMAGE"; then
    echo "错误：无法拉取远程镜像，版本检查失败。"
    return 1
  fi

  local remote_image_id
  local remote_image_created
  local remote_image_digest
  remote_image_id=$(get_image_id)
  remote_image_created=$(get_image_created)
  remote_image_digest=$(get_image_digest)

  echo "======================"
  echo "本地版本(检查前):"
  if [ -n "$local_image_id_before" ]; then
    echo "  镜像ID: $(short_id "$local_image_id_before")"
    echo "  创建时间: ${local_image_created_before:-未知}"
    echo "  摘要: ${local_image_digest_before:-未知}"
  else
    echo "  未检测到本地镜像"
  fi

  echo "远程最新版本:"
  echo "  镜像ID: $(short_id "$remote_image_id")"
  echo "  创建时间: ${remote_image_created:-未知}"
  echo "  摘要: ${remote_image_digest:-未知}"

  if [ "$exists" -eq 1 ]; then
    echo "当前容器使用镜像:"
    echo "  镜像ID: $(short_id "$current_container_image_id")"
  else
    echo "当前容器: 未找到 ${container_name}"
  fi
  echo "======================"

  local update_needed=0
  if [ "$exists" -eq 0 ]; then
    update_needed=1
    echo "提示：未发现容器 ${container_name}，将按最新镜像新建容器。"
  elif [ "$current_container_image_id" != "$remote_image_id" ]; then
    update_needed=1
    echo "检测结果：存在可更新版本。"
  else
    echo "检测结果：当前容器已是最新版本。"
  fi

  if [ "$update_needed" -eq 1 ]; then
    read -p "是否执行更新？(y/N): " do_update </dev/tty
  else
    read -p "是否仍重新部署一次？(y/N): " do_update </dev/tty
  fi

  if [[ "$do_update" != "y" && "$do_update" != "Y" ]]; then
    echo "已取消更新。"
    return 0
  fi

  read -p "请输入宿主机端口 (默认: ${default_port}): " host_port </dev/tty
  host_port=${host_port:-$default_port}
  if ! validate_port "$host_port"; then
    echo "错误：端口无效（范围 1-65535）。"
    return 1
  fi

  read -p "请输入数据存储目录 (默认: ${default_dir}): " host_dir </dev/tty
  host_dir=${host_dir:-$default_dir}
  if [ -z "$host_dir" ]; then
    echo "错误：数据目录不能为空。"
    return 1
  fi

  if [ ! -d "$host_dir" ]; then
    echo "创建目录: $host_dir"
    mkdir -p "$host_dir" || {
      echo "错误：目录创建失败。"
      return 1
    }
  fi

  if [ "$exists" -eq 1 ]; then
    echo "停止并移除旧容器: $container_name"
    docker stop "$container_name" >/dev/null 2>&1 || true
    docker rm "$container_name" >/dev/null 2>&1 || true
  fi

  echo "启动新容器..."
  if run_container "$container_name" "$host_port" "$host_dir" "" ""; then
    echo "======================"
    echo "更新完成！"
    print_access_info "$host_port" "$host_dir" "$container_name"
    echo "======================"
    return 0
  fi

  echo "更新失败，请检查报错信息。"
  return 1
}

main() {
  require_root
  require_docker

  while true; do
    echo "======================"
    echo "Komari 管理菜单："
    echo "  1) 安装 Komari"
    echo "  2) 更新 Komari"
    echo "  0) 退出"
    echo "======================"
    read -p "请选择 (0-2): " choice </dev/tty
    echo

    case "$choice" in
      1) install_komari ;;
      2) update_komari ;;
      0) echo "已退出 Komari 管理。"; exit 0 ;;
      *) echo "无效选项，请重试。" ;;
    esac

    echo
    read -p "按回车继续..." </dev/tty
    echo
  done
}

main
