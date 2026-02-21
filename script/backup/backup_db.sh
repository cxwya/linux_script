#!/bin/bash
# 数据库备份脚本
# 支持：宝塔面板 (MySQL/PgSQL/Mongo/Redis)、Docker (MySQL/PgSQL/Mongo/Redis/SqlSrv/SQLite)
# 功能：列表选择(单选/多选/全选)、自定义目录、自动压缩、生成下载链接

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 权限运行：sudo $0"
  exit 1
fi

# 数据库选择函数
select_databases() {
  local raw_list="$1"
  local db_array=($raw_list)
  
  if [ ${#db_array[@]} -eq 0 ]; then
    echo "NONE"
    return
  fi

  echo "可用数据库列表：" >&2
  local i=1
  for db in "${db_array[@]}"; do
    echo "  $i) $db" >&2
    ((i++))
  done
  echo "  a) 全部数据库 (All)" >&2
  
  read -p "请选择 (输入数字用空格分隔，例如 '1 3'，或 'a'): " selection </dev/tty
  
  if [[ "$selection" == "a" || "$selection" == "A" ]]; then
    echo "ALL"
    return
  fi
  
  local selected_dbs=""
  for idx in $selection; do
    if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#db_array[@]}" ]; then
      selected_dbs="$selected_dbs ${db_array[$((idx-1))]}"
    fi
  done
  
  echo "${selected_dbs:-ALL}"
}

echo "=== 数据库备份 ==="
echo "  1) 宝塔面板数据库"
echo "  2) Docker 容器数据库"
read -p "请选择 (1-2): " type </dev/tty

# 设置备份目录
read -p "请输入备份存放目录 (默认: /root/backup): " BACKUP_DIR </dev/tty
BACKUP_DIR=${BACKUP_DIR:-/root/backup}
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  echo "已创建目录: $BACKUP_DIR"
fi

DATE=$(date +%Y%m%d_%H%M%S)
RAND_STR=$(tr -dc 'a-zA-Z' < /dev/urandom | head -c 6)

# 执行备份
if [ "$type" == "1" ]; then
  # --- 宝塔备份 ---
  echo "正在检测宝塔环境..."
  
  echo "宝塔数据库类型："
  echo "  1) MySQL / MariaDB"
  echo "  2) PostgreSQL"
  echo "  3) MongoDB"
  echo "  4) Redis"
  read -p "请选择 (1-4): " BT_DB_TYPE </dev/tty

  case "$BT_DB_TYPE" in
    1) # MySQL
      # 尝试获取 root 密码
      if [ -f /www/server/panel/data/mysql_root.pl ]; then
        DB_PASS=$(cat /www/server/panel/data/mysql_root.pl)
        echo "已自动获取 MySQL root 密码。"
      else
        echo "未找到宝塔数据库密码文件。"
        read -p "请输入 MySQL root 密码: " DB_PASS </dev/tty
      fi
      
      MYSQL_BIN="/www/server/mysql/bin/mysql"
      MYSQLDUMP="/www/server/mysql/bin/mysqldump"
      [ ! -f "$MYSQL_BIN" ] && MYSQL_BIN="mysql"
      [ ! -f "$MYSQLDUMP" ] && MYSQLDUMP="mysqldump"

      echo "正在获取数据库列表..."
      RAW_DBS=$("$MYSQL_BIN" -u root -p"$DB_PASS" -N -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")
      SELECTED=$(select_databases "$RAW_DBS")
      
      echo "正在导出数据库..."
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED="$RAW_DBS"
      fi
      
      DUMP_FILE="$BACKUP_DIR/bt_mysql-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      for db in $SELECTED; do
        echo "  -> $db"
        "$MYSQLDUMP" -u root -p"$DB_PASS" --databases "$db" > "$DUMP_FILE/${db}.sql" 2>/dev/null
      done
      ;;

    2) # PostgreSQL
      PG_BIN="/www/server/pgsql/bin"
      if [ ! -d "$PG_BIN" ]; then echo "未找到宝塔 PostgreSQL 目录"; exit 1; fi
      
      read -p "数据库用户名 (默认 postgres): " DB_USER </dev/tty
      DB_USER=${DB_USER:-postgres}
      read -p "数据库密码: " DB_PASS </dev/tty
      export PGPASSWORD="$DB_PASS"
      
      echo "正在获取数据库列表..."
      RAW_DBS=$("$PG_BIN/psql" -U "$DB_USER" -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null | tr -d '\r' | xargs)
      SELECTED=$(select_databases "$RAW_DBS")
      
      echo "正在导出数据库..."
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED="$RAW_DBS"
      fi
      
      DUMP_FILE="$BACKUP_DIR/bt_pg-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      for db in $SELECTED; do
        echo "  -> $db"
        "$PG_BIN/pg_dump" -U "$DB_USER" "$db" > "$DUMP_FILE/${db}.sql"
      done
      ;;

    3) # MongoDB
      MONGO_BIN="/www/server/mongodb/bin"
      if [ ! -d "$MONGO_BIN" ]; then echo "未找到宝塔 MongoDB 目录"; exit 1; fi
      read -p "数据库用户名 (root): " DB_USER </dev/tty
      read -p "数据库密码: " DB_PASS </dev/tty
      
      echo "正在获取数据库列表..."
      RAW_DBS=$("$MONGO_BIN/mongosh" --quiet -u "$DB_USER" -p "$DB_PASS" --authenticationDatabase admin --eval "db.adminCommand('listDatabases').databases.forEach(d => print(d.name))" 2>/dev/null)
      if [ -z "$RAW_DBS" ]; then
         RAW_DBS=$("$MONGO_BIN/mongo" --quiet -u "$DB_USER" -p "$DB_PASS" --authenticationDatabase admin --eval "db.adminCommand('listDatabases').databases.forEach(d => print(d.name))" 2>/dev/null)
      fi
      RAW_DBS=$(echo "$RAW_DBS" | grep -Ev "^(admin|config|local)$")
      SELECTED=$(select_databases "$RAW_DBS")
      
      echo "正在导出数据库..."
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED="$RAW_DBS"
      fi
      
      DUMP_FILE="$BACKUP_DIR/bt_mongo-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      for db in $SELECTED; do
        echo "  -> $db"
        "$MONGO_BIN/mongodump" -u "$DB_USER" -p "$DB_PASS" --authenticationDatabase admin --db "$db" --archive > "$DUMP_FILE/${db}.archive"
      done
      ;;

    4) # Redis
      REDIS_CLI="/www/server/redis/src/redis-cli"
      [ ! -f "$REDIS_CLI" ] && REDIS_CLI="redis-cli"
      
      if [ -f "/www/server/redis/redis.conf" ]; then
        CONF_PASS=$(grep "^requirepass" /www/server/redis/redis.conf | awk '{print $2}')
      fi
      if [ -n "$CONF_PASS" ]; then
        echo "已自动获取 Redis 密码。"
        DB_PASS="$CONF_PASS"
      else
        read -p "Redis 密码 (无密码直接回车): " DB_PASS </dev/tty
      fi
      
      DUMP_FILE="$BACKUP_DIR/bt_redis-all-${DATE}-${RAND_STR}.rdb"
      AUTH_ARG=""
      [ -n "$DB_PASS" ] && AUTH_ARG="-a $DB_PASS"
      echo "正在执行 BGSAVE..."
      "$REDIS_CLI" $AUTH_ARG --rdb "$DUMP_FILE" >/dev/null
      ;;
    *) echo "无效选择"; exit 1 ;;
  esac

elif [ "$type" == "2" ]; then
  # --- Docker 备份 ---
  read -p "请输入容器名称或ID: " CONTAINER </dev/tty
  
  echo "数据库类型："
  echo "  1) MySQL / MariaDB"
  echo "  2) PostgreSQL"
  echo "  3) MongoDB"
  echo "  4) Redis"
  echo "  5) SQL Server"
  echo "  6) SQLite"
  read -p "请选择 (1-6): " DB_TYPE_CHOICE </dev/tty
  
  # 根据类型询问账号密码
  if [ "$DB_TYPE_CHOICE" == "6" ]; then
    # SQLite 不需要账号密码
    :
  elif [ "$DB_TYPE_CHOICE" == "4" ]; then
    read -p "Redis 密码 (无密码直接回车): " DB_PASS </dev/tty
  else
    read -p "数据库用户名 (默认根据类型): " DB_USER </dev/tty
    read -p "数据库密码: " DB_PASS </dev/tty
  fi

  case "$DB_TYPE_CHOICE" in
    1) # MySQL / MariaDB
      DB_USER=${DB_USER:-root}
      echo "正在获取数据库列表..."
      RAW_DBS=$(docker exec "$CONTAINER" mysql -u"$DB_USER" -p"$DB_PASS" -N -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "^(information_schema|performance_schema|mysql|sys)$")
      SELECTED=$(select_databases "$RAW_DBS")
      
      echo "正在导出数据库..."
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED="$RAW_DBS"
      fi
      
      DUMP_FILE="$BACKUP_DIR/docker_mysql-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      for db in $SELECTED; do
        echo "  -> $db"
        docker exec "$CONTAINER" mysqldump -u"$DB_USER" -p"$DB_PASS" --databases "$db" > "$DUMP_FILE/${db}.sql"
      done
      ;;

    2) # PostgreSQL
      DB_USER=${DB_USER:-postgres}
      echo "正在获取数据库列表..."
      RAW_DBS=$(docker exec -e PGPASSWORD="$DB_PASS" "$CONTAINER" psql -U "$DB_USER" -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" 2>/dev/null | tr -d '\r' | xargs)
      SELECTED=$(select_databases "$RAW_DBS")

      echo "正在导出数据库..."
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED="$RAW_DBS"
      fi
      
      DUMP_FILE="$BACKUP_DIR/docker_pg-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      for db in $SELECTED; do
        echo "  -> $db"
        docker exec -e PGPASSWORD="$DB_PASS" "$CONTAINER" pg_dump -U "$DB_USER" "$db" > "$DUMP_FILE/${db}.sql"
      done
      ;;

    3) # MongoDB
      DB_USER=${DB_USER:-root}
      echo "正在获取数据库列表..."
      # 尝试使用 mongosh 或 mongo 获取列表
      RAW_DBS=$(docker exec "$CONTAINER" mongosh --quiet -u "$DB_USER" -p "$DB_PASS" --authenticationDatabase admin --eval "db.adminCommand('listDatabases').databases.forEach(d => print(d.name))" 2>/dev/null)
      if [ -z "$RAW_DBS" ]; then
         RAW_DBS=$(docker exec "$CONTAINER" mongo --quiet -u "$DB_USER" -p "$DB_PASS" --authenticationDatabase admin --eval "db.adminCommand('listDatabases').databases.forEach(d => print(d.name))" 2>/dev/null)
      fi
      # 过滤掉系统库
      RAW_DBS=$(echo "$RAW_DBS" | grep -Ev "^(admin|config|local)$")
      
      SELECTED=$(select_databases "$RAW_DBS")
      
      echo "正在导出数据库..."
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED="$RAW_DBS"
      fi
      
      DUMP_FILE="$BACKUP_DIR/docker_mongo-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      for db in $SELECTED; do
        echo "  -> $db"
        docker exec "$CONTAINER" mongodump -u "$DB_USER" -p "$DB_PASS" --authenticationDatabase admin --db "$db" --archive > "$DUMP_FILE/${db}.archive"
      done
      ;;

    4) # Redis
      echo "Redis 通常备份整个实例数据..."
      DUMP_FILE="$BACKUP_DIR/docker_redis-all-${DATE}-${RAND_STR}.rdb"
      # 尝试使用 redis-cli 导出 RDB 到容器内临时文件，然后复制出来
      TEMP_RDB="/tmp/dump-${DATE}-${RAND_STR}.rdb"
      AUTH_ARG=""
      [ -n "$DB_PASS" ] && AUTH_ARG="-a $DB_PASS"
      
      echo "正在执行 BGSAVE..."
      docker exec "$CONTAINER" redis-cli $AUTH_ARG --rdb "$TEMP_RDB" >/dev/null
      if [ $? -eq 0 ]; then
        docker cp "$CONTAINER:$TEMP_RDB" "$DUMP_FILE"
        docker exec "$CONTAINER" rm "$TEMP_RDB"
      else
        echo "redis-cli 导出失败，尝试直接复制 /data/dump.rdb (可能需要暂停写入)..."
        docker cp "$CONTAINER:/data/dump.rdb" "$DUMP_FILE"
      fi
      ;;

    5) # SQL Server
      DB_USER=${DB_USER:-SA}
      echo "正在获取数据库列表..."
      # 使用 sqlcmd 获取列表
      RAW_DBS=$(docker exec "$CONTAINER" /opt/mssql-tools/bin/sqlcmd -S localhost -U "$DB_USER" -P "$DB_PASS" -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','model','msdb','tempdb')" 2>/dev/null | tr -d '\r')
      SELECTED=$(select_databases "$RAW_DBS")
      
      echo "正在导出数据库..."
      DUMP_FILE="$BACKUP_DIR/docker_mssql-multi-${DATE}-${RAND_STR}"
      mkdir -p "$DUMP_FILE"
      
      if [ "$SELECTED" == "ALL" ] || [ "$SELECTED" == "NONE" ]; then
        SELECTED=$RAW_DBS
      fi
      
      for db in $SELECTED; do
        echo "备份: $db"
        TEMP_BAK="/var/opt/mssql/data/${db}-${DATE}-${RAND_STR}.bak"
        docker exec "$CONTAINER" /opt/mssql-tools/bin/sqlcmd -S localhost -U "$DB_USER" -P "$DB_PASS" -Q "BACKUP DATABASE [$db] TO DISK = N'$TEMP_BAK' WITH NOFORMAT, NOINIT, SKIP, NOREWIND, NOUNLOAD, STATS = 10" >/dev/null
        docker cp "$CONTAINER:$TEMP_BAK" "$DUMP_FILE/${db}.bak"
        docker exec "$CONTAINER" rm "$TEMP_BAK"
      done
      ;;

    6) # SQLite
      read -p "请输入容器内 SQLite 数据库文件的绝对路径 (如 /app/data/db.sqlite): " DB_PATH </dev/tty
      DB_NAME=$(basename "$DB_PATH")
      DUMP_FILE="$BACKUP_DIR/docker_sqlite-${DB_NAME}-${DATE}-${RAND_STR}.db"
      echo "正在导出..."
      # 尝试使用 sqlite3 在线备份，如果失败则直接复制文件
      docker exec "$CONTAINER" sqlite3 "$DB_PATH" ".backup '/tmp/sqlite_backup.tmp'" 2>/dev/null
      if [ $? -eq 0 ]; then
        docker cp "$CONTAINER:/tmp/sqlite_backup.tmp" "$DUMP_FILE"
        docker exec "$CONTAINER" rm "/tmp/sqlite_backup.tmp"
      else
        echo "sqlite3 命令不可用，尝试直接复制文件..."
        docker cp "$CONTAINER:$DB_PATH" "$DUMP_FILE"
      fi
      ;;
      
    *) echo "无效选择"; exit 1 ;;
  esac

else
  echo "无效选择"
  exit 1
fi

# 检查备份结果
if [ $? -eq 0 ] && ([ -s "$DUMP_FILE" ] || [ -d "$DUMP_FILE" ]); then
  echo "✓ 备份成功！文件已保存至: $DUMP_FILE"
  
  # 压缩
  echo "正在压缩..."
  GZ_FILE="${DUMP_FILE}.tar.gz"
  tar -czf "$GZ_FILE" -C "$BACKUP_DIR" "$(basename "$DUMP_FILE")"
  rm -rf "$DUMP_FILE"
  
  echo "✓ 压缩完成: $GZ_FILE"
  
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
      if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow "$HTTP_PORT"/tcp >/dev/null 2>&1
        echo "已通过 UFW 开放端口 $HTTP_PORT"
      elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --zone=public --add-port="$HTTP_PORT"/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        echo "已通过 FirewallD 开放端口 $HTTP_PORT"
      elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT >/dev/null 2>&1
        echo "已通过 iptables 开放端口 $HTTP_PORT (临时)"
      fi
      
      # 获取 IP
      IPV4=$(curl -s -4 --connect-timeout 2 ifconfig.me 2>/dev/null)
      [ -z "$IPV4" ] && IPV4=$(hostname -I | awk '{print $1}')
      
      echo "======================"
      echo "正在启动临时 HTTP 服务..."
      echo "下载地址: http://${IPV4}:${HTTP_PORT}/$(basename "$GZ_FILE")"
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
        echo "文件路径: $GZ_FILE"
        PID=""
      fi
      
      if [ -n "$PID" ]; then
        echo "HTTP 服务已在后台运行 (PID: $PID)。"
        echo "您可以断开 SSH 连接，服务不会中断。"
        echo "下载完成后，请运行以下命令停止服务："
        echo "  kill $PID"
      fi
      ;;
    *)
      echo "======================"
      echo "备份结束。"
      echo "文件路径: $GZ_FILE"
      echo "======================"
      ;;
  esac
else
  echo "✗ 备份失败！请检查密码或容器状态。"
  rm -f "$DUMP_FILE"
fi
