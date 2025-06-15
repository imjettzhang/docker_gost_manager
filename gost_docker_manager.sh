#!/bin/bash

DOCKER_IMAGE="gogost/gost:latest"
CONFIG_DIR="/root/gost"
CONTAINER_NAME="gost-manager"
CONFIG_FILE="$CONFIG_DIR/gost.json"

# 日志函数
log_success() {
 echo -e "\e[32m$1\e[0m"
}

log_warning() {
 echo -e "\e[33m$1\e[0m"
}

log_error() {
 echo -e "\e[31m$1\e[0m"
}

# 检查端口是否合法
is_valid_port() {
 local port=$1
 [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# 检查IPv4地址是否合法
is_valid_ipv4() {
 local ip=$1
 if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
   local IFS='.'
   local -a ip_parts=($ip)
   [[ ${ip_parts[0]} -le 255 && ${ip_parts[1]} -le 255 && ${ip_parts[2]} -le 255 && ${ip_parts[3]} -le 255 ]]
   return $?
 fi
 return 1
}

# 检查IPv6地址是否合法
is_valid_ipv6() {
 local ip=$1
 # 更精确的IPv6格式检查，支持各种IPv6格式
 # 完整格式: 2404:c140:1f00:1e::10a0
 # 压缩格式: ::1, ::ffff:192.168.1.1
 # 混合格式等
 if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]] || \
    [[ $ip =~ ^::([0-9a-fA-F]{0,4}:){0,6}[0-9a-fA-F]{0,4}$ ]] || \
    [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,6}:([0-9a-fA-F]{0,4}:){0,5}[0-9a-fA-F]{0,4}$ ]] || \
    [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}:$ ]] || \
    [[ $ip == "::" ]]; then
   return 0
 fi
 return 1
}

# 检查域名是否合法
is_valid_domain() {
 local domain=$1
 [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]
}

# 验证目标地址
validate_target_address() {
 local addr=$1
 if is_valid_ipv4 "$addr"; then
   return 0
 elif is_valid_ipv6 "$addr"; then
   return 0
 elif is_valid_domain "$addr"; then
   return 0
 else
   return 1
 fi
}

# 格式化目标地址（IPv6 自动加方括号）
format_target_address() {
 local addr=$1
 local port=$2
 
 if is_valid_ipv6 "$addr"; then
   # IPv6 地址需要用方括号包围
   echo "[$addr]:$port"
 else
   # IPv4 地址或域名直接使用
   echo "$addr:$port"
 fi
}

print_menu() {
 echo "========= Docker GOST 转发管理脚本 ========="
 echo "1. 安装 Docker 和构建 GOST 镜像"
 echo "2. 创建转发规则"
 echo "3. 查看转发规则"
 echo "4. 删除转发规则" 
 echo "5. 重启 GOST 容器"
 echo "6. 卸载 GOST"
 echo "7. 退出"
 echo "==========================================="
}

# 添加防火墙规则
add_firewall_rule() {
 local port=$1
 local protocol=$2
 
 # 检查是否安装了 ufw
 if command -v ufw &>/dev/null; then
   # 检查 ufw 是否处于活动状态
   if ufw status | grep -q "Status: active"; then
     if [[ $protocol == "tcp" || $protocol == "both" ]]; then
       if ! ufw status | grep -q "$port/tcp"; then
         ufw allow $port/tcp &>/dev/null
         log_success "UFW 防火墙规则已添加：允许 TCP 端口 $port"
       else
         log_warning "TCP 端口 $port 已在 UFW 中开放，无需重复添加"
       fi
     fi
     if [[ $protocol == "udp" || $protocol == "both" ]]; then
       if ! ufw status | grep -q "$port/udp"; then
         ufw allow $port/udp &>/dev/null
         log_success "UFW 防火墙规则已添加：允许 UDP 端口 $port"
       else
         log_warning "UDP 端口 $port 已在 UFW 中开放，无需重复添加"
       fi
     fi
   else
     log_warning "检测到 UFW 但未启用，跳过防火墙配置"
   fi
 else
   log_warning "未检测到 UFW 防火墙，跳过防火墙配置（假设默认放行）"
 fi
}

# 删除防火墙规则
delete_firewall_rule() {
 local port=$1
 local protocol=$2
 
 # 检查是否安装了 ufw
 if command -v ufw &>/dev/null; then
   # 检查 ufw 是否处于活动状态
   if ufw status | grep -q "Status: active"; then
     if [[ $protocol == "tcp" || $protocol == "both" ]]; then
       if ufw status | grep -q "$port/tcp"; then
         ufw delete allow $port/tcp &>/dev/null
         log_success "UFW 防火墙规则已删除：移除 TCP 端口 $port"
       else
         log_warning "TCP 端口 $port 未在 UFW 中开放，无需删除"
       fi
     fi
     if [[ $protocol == "udp" || $protocol == "both" ]]; then
       if ufw status | grep -q "$port/udp"; then
         ufw delete allow $port/udp &>/dev/null
         log_success "UFW 防火墙规则已删除：移除 UDP 端口 $port"
       else
         log_warning "UDP 端口 $port 未在 UFW 中开放，无需删除"
       fi
     fi
   else
     log_warning "检测到 UFW 但未启用，跳过防火墙配置"
   fi
 else
   log_warning "未检测到 UFW 防火墙，跳过防火墙配置"
 fi
}

install_docker_and_gost() {
 echo ">>> 安装 Docker..."
 if ! command -v docker &>/dev/null; then
   curl -fsSL https://get.docker.com | bash
   systemctl start docker
   systemctl enable docker
 else
   log_success "Docker 已安装"
 fi

 # 检查是否已存在 GOST 容器
 if docker ps -a | grep -q $CONTAINER_NAME; then
   log_warning "检测到已存在的 GOST 容器！"
   
   while true; do
     read -p "是否确认覆盖安装？这将清空所有转发规则 (y/n): " confirm
     case $confirm in
       [Yy]|[Yy][Ee][Ss])
         echo ">>> 正在卸载现有 GOST..."
         docker stop $CONTAINER_NAME 2>/dev/null
         docker rm $CONTAINER_NAME 2>/dev/null
         log_success "现有容器已删除"
         break
         ;;
       [Nn]|[Nn][Oo])
         log_warning "安装已取消"
         return 0
         ;;
       *)
         log_error "请输入 y 或 n"
         ;;
     esac
   done
 fi

 mkdir -p $CONFIG_DIR
 
 # 创建空配置文件
 cat > $CONFIG_FILE << 'EOF'
{
  "services": []
}
EOF

 # 拉取并运行 GOST 容器
 echo ">>> 拉取 GOST 镜像..."
 docker pull $DOCKER_IMAGE
 
 echo ">>> 启动 GOST 容器..."
 docker run -d \
   --name $CONTAINER_NAME \
   --restart always \
   --network host \
   -v $CONFIG_FILE:/etc/gost/gost.json \
   $DOCKER_IMAGE

 if docker ps | grep -q $CONTAINER_NAME; then
   log_success "GOST 已安装并运行！"
 else
   log_error "GOST 容器启动失败，请检查日志："
   docker logs --tail 10 $CONTAINER_NAME
 fi
}

create_rule() {
 echo ">>> 添加转发规则"
 
 # 检查并安装 jq
 if ! check_and_install_jq; then
   log_error "无法安装 jq 工具，操作中止"
   return 1
 fi
 
 # 验证本地端口
 while true; do
   read -p "输入本地监听端口: " listen_port
   if ! is_valid_port "$listen_port"; then
     log_error "无效的端口号！请输入 1-65535 之间的数字"
   else
     break
   fi
 done
 
 # 验证目标地址
 while true; do
   read -p "输入目标地址 (IPv4, IPv6 或域名): " target_addr
   if validate_target_address "$target_addr"; then
     break
   else
     log_error "无效的目标地址！请输入正确的 IPv4、IPv6 地址或域名"
   fi
 done
 
 # 验证目标端口
 while true; do
   read -p "输入目标端口: " target_port
   if ! is_valid_port "$target_port"; then
     log_error "无效的端口号！请输入 1-65535 之间的数字"
   else
     break
   fi
 done

 # 显示格式化后的目标地址确认
 local formatted_target=$(format_target_address "$target_addr" "$target_port")
 echo ""
 echo ">>> 转发配置确认："
 echo "本地端口: $listen_port"
 echo "目标地址: $formatted_target"
 if is_valid_ipv6 "$target_addr"; then
   log_success "检测到 IPv6 地址，已自动添加方括号格式"
 fi
 echo ""

 echo "请选择协议："
 echo "1: TCP"
 echo "2: UDP"
 echo "3: TCP + UDP"
 read -p "请输入 (1/2/3): " protocol_choice

 # 备份现有配置
 cp $CONFIG_FILE $CONFIG_FILE.bak

 # 添加新规则到 JSON 配置
 add_service_to_json() {
   local service_name=$1
   local protocol=$2
   local has_metadata=$3
   
   # 格式化目标地址（IPv6 自动加方括号）
   local formatted_target=$(format_target_address "$target_addr" "$target_port")
   
   # 使用 jq 添加服务到配置文件
   if [ "$has_metadata" = "true" ]; then
     # UDP 服务，包含 metadata
     jq --arg name "$service_name" \
        --arg addr ":$listen_port" \
        --arg type "$protocol" \
        --arg target "$formatted_target" \
        '.services += [{
          "name": $name,
          "addr": $addr,
          "handler": {"type": $type},
          "listener": {"type": $type},
          "metadata": {
            "keepAlive": true,
            "ttl": "5s",
            "readBufferSize": 4096
          },
          "forwarder": {
            "nodes": [{"name": "target-0", "addr": $target}]
          }
        }]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
   else
     # TCP 服务，不包含 metadata
     jq --arg name "$service_name" \
        --arg addr ":$listen_port" \
        --arg type "$protocol" \
        --arg target "$formatted_target" \
        '.services += [{
          "name": $name,
          "addr": $addr,
          "handler": {"type": $type},
          "listener": {"type": $type},
          "forwarder": {
            "nodes": [{"name": "target-0", "addr": $target}]
          }
        }]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
   fi
 }

 case $protocol_choice in
   1) 
     # TCP 转发配置
     add_service_to_json "service-tcp-$listen_port" "tcp" "false"
     add_firewall_rule "$listen_port" "tcp"
     ;;
   2)
     # UDP 转发配置
     add_service_to_json "service-udp-$listen_port" "udp" "true"
     add_firewall_rule "$listen_port" "udp"
     ;;
   3)
     # TCP + UDP 转发配置
     add_service_to_json "service-tcp-$listen_port" "tcp" "false"
     add_service_to_json "service-udp-$listen_port" "udp" "true"
     add_firewall_rule "$listen_port" "both"
     ;;
   *)
     log_error "无效的选择！"
     return 1
     ;;
 esac

 docker restart $CONTAINER_NAME
 sleep 2

 local proto=""
 case $protocol_choice in
   1) proto="TCP" ;;
   2) proto="UDP" ;;
   3) proto="TCP + UDP" ;;
 esac
 
 # 重新获取格式化的目标地址用于显示
 local display_target=$(format_target_address "$target_addr" "$target_port")
 
 if netstat -tunlp | grep -q ":$listen_port.*gost"; then
   log_success "转发规则已添加并生效！"
   echo ">>> 转发详情:"
   echo "本地端口: $listen_port -> 目标: $display_target"
   echo "协议: $proto"
 else
   log_warning "转发规则已添加，但端口未正常监听，请检查日志："
   docker logs --tail 10 $CONTAINER_NAME
 fi
}

view_rules() {
 # 直接使用简洁的列表格式显示规则
 if ! list_rules_for_deletion; then
   return 1
 fi
 
 echo -e "\n>>> 当前端口监听状态："
 netstat -tunlp | grep gost || echo "未检测到 GOST 监听的端口"
}

# 检查和安装 jq 工具
check_and_install_jq() {
 if ! command -v jq &>/dev/null; then
   log_warning "jq 工具未安装，正在尝试安装..."
   
   # 尝试使用包管理器安装
   if command -v apt-get &>/dev/null; then
     apt-get update && apt-get install -y jq
   elif command -v yum &>/dev/null; then
     yum install -y jq
   elif command -v dnf &>/dev/null; then
     dnf install -y jq
   else
     # 手动下载安装
     local jq_url="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64"
     if curl -L "$jq_url" -o /tmp/jq && chmod +x /tmp/jq; then
       mv /tmp/jq /usr/local/bin/jq
       log_success "jq 工具安装成功"
     else
       log_error "jq 工具安装失败，无法继续操作"
       return 1
     fi
   fi
   
   if command -v jq &>/dev/null; then
     log_success "jq 工具安装成功"
   else
     log_error "jq 工具安装失败，无法继续操作"
     return 1
   fi
 fi
 return 0
}

# 列出当前所有转发规则
list_rules_for_deletion() {
 echo ">>> 当前转发规则列表："
 
 if ! [ -f "$CONFIG_FILE" ]; then
   log_warning "配置文件不存在"
   return 1
 fi
 
 # 使用 jq 精确提取信息
 local services=$(jq -r '.services[] | select(.name | test("service-(tcp|udp)-[0-9]+")) | "\(.name) -> \(.addr) (\(.handler.type)) -> \(.forwarder.nodes[0].addr)"' "$CONFIG_FILE" 2>/dev/null)
 
 if [ -z "$services" ]; then
   log_warning "未找到任何转发规则"
   return 1
 fi
 
 local rule_count=0
 echo "$services" | while IFS= read -r line; do
   rule_count=$((rule_count + 1))
   echo "$rule_count. $line"
 done
 
 return 0
}

delete_rule() {
 echo ">>> 删除转发规则"
 
 # 检查并安装 jq
 if ! check_and_install_jq; then
   log_error "无法安装 jq 工具，操作中止"
   return 1
 fi
 
 # 显示当前规则
 if ! list_rules_for_deletion; then
   return 1
 fi
 
 echo ""
 read -p "输入要删除的监听端口: " port
 
 if ! is_valid_port "$port"; then
   log_error "无效的端口号！请输入 1-65535 之间的数字"
   return 1
 fi

 # 检查端口是否存在
 if ! grep -q "service-.*-$port" "$CONFIG_FILE"; then
   log_error "端口 $port 的转发规则不存在！"
   return 1
 fi

 # 备份配置文件
 cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"

 # 使用 jq 精确删除规则
 log_success "使用 jq 工具删除规则..."
 
 # 删除所有匹配端口的服务（TCP 和 UDP）
 jq --arg port "$port" '.services |= map(select(.name | test("service-(tcp|udp)-" + $port + "$") | not))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
 
 # 检查删除结果
 if ! grep -q "service-.*-$port" "$CONFIG_FILE"; then
   log_success "成功删除端口 $port 的规则！"
 else
   log_error "删除失败，恢复备份文件..."
   # 恢复备份文件
   latest_backup=$(ls -t "$CONFIG_FILE.bak."* | head -1)
   cp "$latest_backup" "$CONFIG_FILE"
   return 1
 fi

 # 删除防火墙规则
 delete_firewall_rule "$port" "both"

 # 重启 GOST 容器以使配置生效
 echo ">>> 重启 GOST 容器..."
 docker restart $CONTAINER_NAME
 sleep 2

 # 验证删除结果
 if docker ps | grep -q $CONTAINER_NAME; then
   log_success "GOST 容器重启成功！"
   if ! netstat -tunlp | grep -q ":$port.*gost"; then
     log_success "端口 $port 已停止监听，删除成功！"
   else
     log_warning "端口 $port 仍在监听，请检查配置"
   fi
 else
   log_error "GOST 容器启动失败，请检查配置："
   docker logs --tail 10 $CONTAINER_NAME
 fi
}

restart_container() {
 docker restart $CONTAINER_NAME
 sleep 2
 if docker ps | grep -q $CONTAINER_NAME; then
   log_success "GOST 容器已重启！"
   echo ">>> 当前端口监听状态："
   netstat -tunlp | grep "gost" || echo "未检测到 GOST 监听的端口"
 else
   log_error "GOST 容器启动失败，请检查配置："
   docker logs --tail 10 $CONTAINER_NAME
 fi
}

uninstall_gost() {
 if docker ps -a | grep -q $CONTAINER_NAME; then
   docker stop $CONTAINER_NAME
   docker rm $CONTAINER_NAME
   rm -rf $CONFIG_DIR
   log_success "GOST 已卸载！"
 else
   log_warning "GOST 未安装！"
 fi
}

# 主循环
while true; do
 print_menu
 read -p "请选择操作: " choice
 case $choice in
   1) install_docker_and_gost ;;
   2) create_rule ;;
   3) view_rules ;;
   4) delete_rule ;;
   5) restart_container ;;
   6) uninstall_gost ;;
   7)
     echo "退出脚本！"
     exit 0
     ;;
   *)
     log_error "无效的选择！"
     ;;
 esac
done