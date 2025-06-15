#!/bin/bash

DOCKER_IMAGE="gogost/gost:latest"
CONFIG_DIR="/root/gost"
CONTAINER_NAME="gost-manager"

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
 # 简单的IPv6格式检查
 [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]
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
 if [[ $protocol == "tcp" || $protocol == "both" ]]; then
   if ! iptables -C INPUT -p tcp --dport $port -j ACCEPT &>/dev/null; then
     iptables -A INPUT -p tcp --dport $port -j ACCEPT
     log_success "防火墙规则已添加：允许 TCP 端口 $port"
   else
     log_warning "TCP 端口 $port 已开放，无需重复添加"
   fi
 fi
 if [[ $protocol == "udp" || $protocol == "both" ]]; then
   if ! iptables -C INPUT -p udp --dport $port -j ACCEPT &>/dev/null; then
     iptables -A INPUT -p udp --dport $port -j ACCEPT
     log_success "防火墙规则已添加：允许 UDP 端口 $port"
   else
     log_warning "UDP 端口 $port 已开放，无需重复添加"
   fi
 fi
 iptables-save > /etc/iptables/rules.v4
}

# 删除防火墙规则
delete_firewall_rule() {
 local port=$1
 local protocol=$2
 if [[ $protocol == "tcp" || $protocol == "both" ]]; then
   if iptables -C INPUT -p tcp --dport $port -j ACCEPT &>/dev/null; then
     iptables -D INPUT -p tcp --dport $port -j ACCEPT
     log_success "防火墙规则已删除：阻止 TCP 端口 $port"
   else
     log_warning "TCP 端口 $port 未开放，无需删除"
   fi
 fi
 if [[ $protocol == "udp" || $protocol == "both" ]]; then
   if iptables -C INPUT -p udp --dport $port -j ACCEPT &>/dev/null; then
     iptables -D INPUT -p udp --dport $port -j ACCEPT
     log_success "防火墙规则已删除：阻止 UDP 端口 $port"
   else
     log_warning "UDP 端口 $port 未开放，无需删除"
   fi
 fi
 iptables-save > /etc/iptables/rules.v4
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
   echo ">>> 当前容器状态："
   docker ps -a | grep $CONTAINER_NAME
   
   if [ -f "$CONFIG_DIR/gost.yml" ]; then
     echo -e "\n>>> 当前转发规则："
     cat $CONFIG_DIR/gost.yml
   fi
   
   echo -e "\n警告：重新安装将会："
   echo "1. 停止并删除现有容器"
   echo "2. 清空所有转发规则"
   echo "3. 重置配置文件"
   
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
 cat > $CONFIG_DIR/gost.yml << 'EOF'
services:
EOF

 # 拉取并运行 GOST 容器
 echo ">>> 拉取 GOST 镜像..."
 docker pull $DOCKER_IMAGE
 
 echo ">>> 启动 GOST 容器..."
 docker run -d \
   --name $CONTAINER_NAME \
   --restart always \
   --network host \
   -v $CONFIG_DIR/gost.yml:/etc/gost/gost.yml \
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

 echo "请选择协议："
 echo "1: TCP"
 echo "2: UDP"
 echo "3: TCP + UDP"
 read -p "请输入 (1/2/3): " protocol_choice

 # 备份现有配置
 cp $CONFIG_DIR/gost.yml $CONFIG_DIR/gost.yml.bak

 case $protocol_choice in
   1) 
     # TCP 转发配置
     cat >> $CONFIG_DIR/gost.yml << EOF
 - name: service-tcp-$listen_port
   addr: :$listen_port
   handler:
     type: tcp
   listener:
     type: tcp
   forwarder:
     nodes:
       - name: target-0
         addr: $target_addr:$target_port
EOF
     add_firewall_rule "$listen_port" "tcp"
     ;;
   2)
     # UDP 转发配置
     cat >> $CONFIG_DIR/gost.yml << EOF
 - name: service-udp-$listen_port
   addr: :$listen_port
   handler:
     type: udp
   listener:
     type: udp
   metadata:
     keepAlive: true
     ttl: 5s
     readBufferSize: 4096
   forwarder:
     nodes:
       - name: target-0
         addr: $target_addr:$target_port
EOF
     add_firewall_rule "$listen_port" "udp"
     ;;
   3)
     # TCP + UDP 转发配置
     cat >> $CONFIG_DIR/gost.yml << EOF
 - name: service-tcp-$listen_port
   addr: :$listen_port
   handler:
     type: tcp
   listener:
     type: tcp
   forwarder:
     nodes:
       - name: target-0
         addr: $target_addr:$target_port
 - name: service-udp-$listen_port
   addr: :$listen_port
   handler:
     type: udp
   listener:
     type: udp
   metadata:
     keepAlive: true
     ttl: 5s
     readBufferSize: 4096
   forwarder:
     nodes:
       - name: target-0
         addr: $target_addr:$target_port
EOF
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
 
 if netstat -tunlp | grep -q ":$listen_port.*gost"; then
   log_success "转发规则已添加并生效！"
   echo ">>> 转发详情:"
   echo "本地端口: $listen_port -> 目标: $target_addr:$target_port"
   echo "协议: $proto"
 else
   log_warning "转发规则已添加，但端口未正常监听，请检查日志："
   docker logs --tail 10 $CONTAINER_NAME
 fi
}

view_rules() {
 echo ">>> 当前转发规则："
 if [ -f "$CONFIG_DIR/gost.yml" ]; then
   cat $CONFIG_DIR/gost.yml
   echo -e "\n>>> 当前端口监听状态："
   netstat -tunlp | grep gost || echo "未检测到 GOST 监听的端口"
 else
   log_warning "配置文件不存在"
 fi
}

delete_rule() {
 echo ">>> 删除转发规则"
 read -p "输入要删除的监听端口: " port
 
 if ! is_valid_port "$port"; then
   log_error "无效的端口号！请输入 1-65535 之间的数字"
   return 1
 fi

 # 创建临时文件
 tmp_file=$(mktemp)
 
 # 写入 services: 行（只写入一次）
 echo "services:" > "$tmp_file"

 # 用于判断是否在要删除的服务块中
 skip_block=false
 
 # 逐行处理配置文件，跳过第一行的 services:
 tail -n +2 "$CONFIG_DIR/gost.yml" | while IFS= read -r line; do
   # 检查新的服务块开始
   if [[ $line =~ ^[[:space:]]-[[:space:]]name:[[:space:]]service-(tcp|udp)-([0-9]+)$ ]]; then
     service_port="${BASH_REMATCH[2]}"
     # 精确匹配端口号
     if [ "$service_port" = "$port" ]; then
       skip_block=true
     else
       skip_block=false
       echo "$line" >> "$tmp_file"
     fi
   elif [[ $line =~ ^[[:space:]]-[[:space:]]name: ]]; then
     # 新的非端口相关服务块开始
     skip_block=false
     echo "$line" >> "$tmp_file"
   elif [ "$skip_block" = "false" ]; then
     # 如果不在要删除的块中，就写入行
     echo "$line" >> "$tmp_file"
   fi
 done

 # 更新配置文件
 mv "$tmp_file" "$CONFIG_DIR/gost.yml"

 # 删除防火墙规则
 delete_firewall_rule "$port" "both"

 # 重启 GOST 容器以使配置生效
 docker restart $CONTAINER_NAME
 sleep 2

 # 检查是否成功删除
 if grep -q "service.*(tcp|udp)-$port[[:space:]]*$" "$CONFIG_DIR/gost.yml"; then
   log_error "删除失败！端口 $port 的规则仍存在于配置文件中"
 else
   log_success "端口 $port 的规则已成功删除！"
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