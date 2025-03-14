#!/usr/bin/env bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
stty erase ^?

cd "$(
  cd "$(dirname "$0")" || exit
  pwd
)" || exit

# 字体颜色配置
Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[36m"
Font="\033[0m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
OK="${Green}[OK]${Font}"
ERROR="${Red}[ERROR]${Font}"

# 变量
dino_version="v1.0.0"
xray_version="v25.3.6"
stat_dir="/usr/local/bin/stat"
xray_admin_dir="/usr/local/bin/xray-admin"
xray_admin_conf_dir="/usr/local/etc/xray-admin"
xray_admin_service_dir="/etc/systemd/system/xray_admin.service"
stat_service_dir="/etc/systemd/system/stat.service"
xray_conf_dir="/usr/local/etc/xray"
website_dir="/www/xray_web/"
xray_access_log="/var/log/xray/access.log"
xray_error_log="/var/log/xray/error.log"
iptables_conf_dir="/usr/local/etc/xray/iptables"

VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

function print_ok() {
  echo -e "${OK} ${Blue} $1 ${Font}"
}

function print_error() {
  echo -e "${ERROR} ${RedBG} $1 ${Font}"
}

function is_root() {
  if [[ 0 == "$UID" ]]; then
    print_ok "当前用户是 root 用户，开始安装流程"
  else
    print_error "当前用户不是 root 用户，请切换到 root 用户后重新执行脚本"
    exit 1
  fi
}

judge() {
  if [[ 0 -eq $? ]]; then
    print_ok "$1 完成"
    sleep 1
  else
    print_error "$1 失败"
    exit 1
  fi
}

function system_check() {
  source '/etc/os-release'

  if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
    print_ok "当前系统为 Centos ${VERSION_ID} ${VERSION}"
    INS="yum install -y"
    ${INS} wget
    wget -N -P /etc/yum.repos.d/ https://raw.githubusercontent.com/gongshen/dino/main/resource/nginx.repo


  elif [[ "${ID}" == "ol" ]]; then
    print_ok "当前系统为 Oracle Linux ${VERSION_ID} ${VERSION}"
    INS="yum install -y"
    wget -N -P /etc/yum.repos.d/ https://raw.githubusercontent.com/gongshen/dino/main/resource/nginx.repo
  elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 9 ]]; then
    print_ok "当前系统为 Debian ${VERSION_ID} ${VERSION}"
    INS="apt install -y"
    # 清除可能的遗留问题
    rm -f /etc/apt/sources.list.d/nginx.list
    # nginx 安装预处理
    $INS curl gnupg2 ca-certificates lsb-release debian-archive-keyring
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/debian `lsb_release -cs` nginx" \
    | tee /etc/apt/sources.list.d/nginx.list
    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | tee /etc/apt/preferences.d/99nginx

    apt update

  elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 18 ]]; then
    print_ok "当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME}"
    INS="apt install -y"
    # 清除可能的遗留问题
    rm -f /etc/apt/sources.list.d/nginx.list
    # nginx 安装预处理
    $INS curl gnupg2 ca-certificates lsb-release ubuntu-keyring
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/ubuntu `lsb_release -cs` nginx" \
    | tee /etc/apt/sources.list.d/nginx.list
    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    | tee /etc/apt/preferences.d/99nginx

    apt update
  else
    print_error "当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内"
    exit 1
  fi

  $INS dbus

  # 关闭各类防火墙
  systemctl stop firewalld
  systemctl disable firewalld
  systemctl stop nftables
  systemctl disable nftables
  systemctl stop ufw
  systemctl disable ufw
}

function nginx_install() {
  if ! command -v nginx >/dev/null 2>&1; then
    ${INS} nginx
    judge "Nginx 安装"
  else
    print_ok "Nginx 已存在"
  fi
  # 遗留问题处理
  mkdir -p /etc/nginx/conf.d >/dev/null 2>&1
}
function dependency_install() {
  ${INS} lsof tar
  judge "安装 lsof tar"

  if [[ "${ID}" == "centos" || "${ID}" == "ol" ]]; then
    ${INS} crontabs
  else
    ${INS} cron
  fi
  judge "安装 crontab"

  if [[ "${ID}" == "centos" || "${ID}" == "ol" ]]; then
    touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
    systemctl start crond && systemctl enable crond
  else
    touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
    systemctl start cron && systemctl enable cron

  fi
  judge "crontab 自启动配置 "

  ${INS} unzip
  judge "安装 unzip"

  ${INS} curl
  judge "安装 curl"

  # upgrade systemd
  ${INS} systemd
  judge "安装/升级 systemd"

  # Nginx 后置 无需编译 不再需要
  #  if [[ "${ID}" == "centos" ||  "${ID}" == "ol" ]]; then
  #    yum -y groupinstall "Development tools"
  #  else
  #    ${INS} build-essential
  #  fi
  #  judge "编译工具包 安装"

  if [[ "${ID}" == "centos" ]]; then
    ${INS} pcre pcre-devel zlib-devel epel-release openssl openssl-devel
  elif [[ "${ID}" == "ol" ]]; then
    ${INS} pcre pcre-devel zlib-devel openssl openssl-devel
    # Oracle Linux 不同日期版本的 VERSION_ID 比较乱 直接暴力处理。如出现问题或有更好的方案，请提交 Issue。
    yum-config-manager --enable ol7_developer_EPEL >/dev/null 2>&1
    yum-config-manager --enable ol8_developer_EPEL >/dev/null 2>&1
  else
    ${INS} libpcre3 libpcre3-dev zlib1g-dev openssl libssl-dev
  fi

  ${INS} jq

  if ! command -v jq; then
    wget -P /usr/bin https://github.com/gongshen/dino/releases/download/${dino_version}/jq && chmod +x /usr/bin/jq
    judge "安装 jq"
  fi

  wget --no-check-certificate https://copr.fedorainfracloud.org/coprs/ngompa/musl-libc/repo/epel-7/ngompa-musl-libc-epel-7.repo -O /etc/yum.repos.d/ngompa-musl-libc-epel-7.repo
  ${INS} musl-libc-static
  judge "安装musl静态库"

  # 防止部分系统xray的默认bin目录缺失
  mkdir /usr/local/bin >/dev/null 2>&1
}

function basic_optimization() {
  # 最大文件打开数
  sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
  sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
  echo '* soft nofile 65536' >>/etc/security/limits.conf
  echo '* hard nofile 65536' >>/etc/security/limits.conf

  # RedHat 系发行版关闭 SELinux
  if [[ "${ID}" == "centos" || "${ID}" == "ol" ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    setenforce 0
  fi
}

function domain_check() {
  read -rp "请输入你的域名信息(eg: www.wulabing.com):" domain
  domain_ip=$(curl -sm8 ipget.net/?ip="${domain}")
  print_ok "正在获取 IP 地址信息，请耐心等待"
  wgcfv4_status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
  if [[ ${wgcfv4_status} =~ "on"|"plus" ]] || [[ ${wgcfv6_status} =~ "on"|"plus" ]]; then
    # 关闭wgcf-warp，以防误判VPS IP情况
    wg-quick down wgcf >/dev/null 2>&1
    print_ok "已关闭 wgcf-warp"
  fi
  local_ipv4=$(curl -s4m8 ip.gs)
  echo -e "域名通过 DNS 解析的 IP 地址：${domain_ip}"
  echo -e "本机公网 IPv4 地址： ${local_ipv4}"
  sleep 2
  if [[ ${domain_ip} == "${local_ipv4}" ]]; then
    print_ok "域名通过 DNS 解析的 IP 地址与 本机 IPv4 地址匹配"
    sleep 2
  else
    print_error "请确保域名添加了正确的 A / AAAA 记录，否则将无法正常使用 xray"
    print_error "域名通过 DNS 解析的 IP 地址与 本机 IPv4 地址不匹配，是否继续安装？（y/n）" && read -r install
    case $install in
    [yY][eE][sS] | [yY])
      print_ok "继续安装"
      sleep 2
      ;;
    *)
      print_error ip"安装终止"
      exit 2
      ;;
    esac
  fi
}

function port_exist_check() {
  if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
    print_ok "$1 端口未被占用"
    sleep 1
  else
    print_error "检测到 $1 端口被占用，以下为 $1 端口占用信息"
    lsof -i:"$1"
    print_error "5s 后将尝试自动 kill 占用进程"
    sleep 5
    lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
    print_ok "kill 完成"
    sleep 1
  fi
}

function configure_nginx() {
  nginx_conf="/etc/nginx/nginx.conf"
  cd /etc/nginx/ && rm -f nginx.conf && wget -O nginx.conf https://raw.githubusercontent.com/gongshen/dino/main/resource/nginx.conf
  sed -i "s/xxx/${domain}/g" ${nginx_conf}
  judge "Nginx 配置 修改"

  systemctl enable nginx
  systemctl restart nginx
}

function modify_UUID() {
  [ -z "$UUID" ] && UUID=$(cat /proc/sys/kernel/random/uuid)
  cat ${xray_conf_dir}/config.json | jq 'setpath(["inbounds",0,"settings","clients",0,"id"];"'${UUID}'")' >${xray_conf_dir}/config_tmp.json
  xray_tmp_config_file_check_and_use
  judge "Xray TCP UUID 修改"
}

function configure_xray() {
  cd  ${xray_conf_dir} && rm -f config.json && wget -O config.json https://raw.githubusercontent.com/gongshen/dino/main/resource/xrayConfig.json
  modify_UUID
  modify_port
  systemctl restart xray
  judge "Xray 启动"
}

function xray_install() {
  print_ok "安装 Xray"
  curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- install --version ${xray_version}
  judge "Xray 安装"
}

function configure_web() {
  rm -rf /www/xray_web
  mkdir -p /www/xray_web
  print_ok "是否配置伪装网页？[Y/N]"
  read -r webpage
  case $webpage in
  [yY][eE][sS] | [yY])
    wget -O web.tar.gz https://raw.githubusercontent.com/gongshen/xray/main/base/web.tar.gz
    tar xzf web.tar.gz -C /www/xray_web
    judge "站点伪装"
    rm -f web.tar.gz
    ;;
  *) ;;
  esac
}

function xray_uninstall() {
  curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- remove --purge
  rm -rf $website_dir
  print_ok "是否卸载nginx [Y/N]?"
  read -r uninstall_nginx
  case $uninstall_nginx in
  [yY][eE][sS] | [yY])
    if [[ "${ID}" == "centos" || "${ID}" == "ol" ]]; then
      yum remove nginx -y
    else
      apt purge nginx -y
    fi
    ;;
  *) ;;
  esac
  print_ok "卸载完成"
  exit 0
}

function restart_all() {
  systemctl restart xray
  judge "Xray 启动"
  systemctl restart stat
  judge "Stat 启动"
}

function basic_information() {
  UUID=$(cat ${xray_conf_dir}/config.json | jq .inbounds[0].settings.clients[0].id | tr -d '"')
  PORT=$(cat ${xray_conf_dir}/config.json | jq .inbounds[0].port)
  EMAIL=$(cat ${xray_conf_dir}/config.json | jq .inbounds[0].settings.clients[0].email | tr -d '"')
  echo -e "${Blue}用户:${Font} $EMAIL"
  echo -e "${Blue}uuid:${Font} $UUID"
  echo -e "${Blue}port:${Font} $PORT"
  echo -e "${Blue}alterId:${Font} （dino2模式默认64）"
}

function vless_xtls-rprx-direct_link() {
  UUID=$(cat ${xray_conf_dir}/config.json | jq .inbounds[0].settings.clients[0].id | tr -d '"')
  PORT=$(cat ${xray_conf_dir}/config.json | jq .inbounds[0].port)
  FLOW=$(cat ${xray_conf_dir}/config.json | jq .inbounds[0].settings.clients[0].flow | tr -d '"')

  print_ok "URL 链接 (VLESS + TCP + TLS)"
  print_ok "vless://$UUID@$DOMAIN:$PORT?security=tls&flow=$FLOW#dino"

  print_ok "URL 链接 (VLESS + TCP + XTLS)"
  print_ok "vless://$UUID@$DOMAIN:$PORT?security=xtls&flow=$FLOW#XTLS_wulabing-$DOMAIN"
  print_ok "-------------------------------------------------"
  print_ok "URL 二维码 (VLESS + TCP + TLS) （请在浏览器中访问）"
  print_ok "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless://$UUID@$DOMAIN:$PORT?security=tls%26flow=$FLOW%23TLS_wulabing-$DOMAIN"

  print_ok "URL 二维码 (VLESS + TCP + XTLS) （请在浏览器中访问）"
  print_ok "https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=vless://$UUID@$DOMAIN:$PORT?security=xtls%26flow=$FLOW%23XTLS_wulabing-$DOMAIN"
}

function show_access_log() {
  [ -f ${xray_access_log} ] && tail -f ${xray_access_log} || echo -e "${RedBG}log 文件不存在${Font}"
}

function show_error_log() {
  [ -f ${xray_error_log} ] && tail -f ${xray_error_log} || echo -e "${RedBG}log 文件不存在${Font}"
}

function bbr_boost_sh() {
  [ -f "tcp.sh" ] && rm -rf ./tcp.sh
  wget -N --no-check-certificate "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh && ./tcp.sh
}

function config_iptables() {
  # 下载iptables文件
  wget -O iptables https://raw.githubusercontent.com/gongshen/dino/main/resource/iptables && mv -f iptables ${iptables_conf_dir}
  # 循环提示用户输入SSH端口，直到输入非空值
  while true; do
    read -rp "请输入ssh端口号：" SSHPORT
    if [[ -n "$SSHPORT" ]]; then
      break
    else
      print_error "SSH端口不能为空，请重新输入"
    fi
  done
  sed -i "s|__SSHPORT__|${SSHPORT}|" ${iptables_conf_dir}
  read -rp "请输入管理端ip地址：" remoteIp
  sed -i "s|__ADMINIP__|${remoteIp}|" ${iptables_conf_dir}

  # 提示用户是否是管理员
  read -rp "Is Admin? (yes/y or no/n): " is_admin
  
  # 如果用户输入yes或y，请求用户输入ADMINPORT的值
  if [[ "$is_admin" == "yes" || "$is_admin" == "y" ]]; then
    while true; do
      read -rp "请输入管理员端口号：" ADMINPORT
      if [[ -n "$ADMINPORT" ]]; then
        break
      else
        print_error "管理员端口不能为空，请重新输入"
      fi
    done
    sed -i "s|###||" ${iptables_conf_dir}
    sed -i "s|__ADMINPORT__|${ADMINPORT}|" ${iptables_conf_dir}
  fi

  iptables-restore < ${iptables_conf_dir}
  systemctl restart iptables
}

function install_stat() {
  cd /root
  wget -O stat https://github.com/gongshen/dino/releases/download/${dino_version}/stat && chmod +x stat && mv -f stat ${stat_dir}
  wget -O stat.service https://raw.githubusercontent.com/gongshen/dino/main/resource/stat.service && mv -f stat.service ${stat_service_dir}
  read -rp "请输入管理端ip地址：" remoteIp
  sed -i "s|__REMOTE_IP__|${remoteIp}|" ${stat_service_dir}
  systemctl daemon-reload
  systemctl enable stat
  systemctl restart stat
  judge "Stat 启动"
}

function install_mysql() {
  # 安装mysql8.0
  yum update -y
  rpm -Uvh https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm
  rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2022
  yum install mysql-server -y
  # 获取MySQL初始化密码
  MYSQL_INIT_PASSWORD=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
  # 输入新密码
  echo "Enter new password for MySQL user: "
  read NEW_MYSQL_PASSWORD
  # 更改MySQL用户密码
  mysql --connect-expired-password -uroot -p"$MYSQL_INIT_PASSWORD" <<EOF
  ALTER USER 'root'@'localhost' IDENTIFIED BY '$NEW_MYSQL_PASSWORD';
EOF

  echo "Password updated successfully!"
}

function install_admin() {
  cd /root
  # 安装xray-admin
  wget -O xray-admin.tar.gz https://github.com/gongshen/dino/raw/main/resource/xray-admin.tar.gz
  rm -rf resource
  tar -xzvf xray-admin.tar.gz
  chmod +x xray-admin
  mv -f xray-admin ${xray_admin_dir}
  rm -rf xray-admin.tar.gz
  # 下载管理端配置文件
  if [ ! -d ${xray_admin_conf_dir} ]; then
    mkdir -p ${xray_admin_conf_dir}
  fi
  cd  ${xray_admin_conf_dir} && rm -f config.yaml && wget -O config.yaml https://raw.githubusercontent.com/gongshen/dino/main/resource/xray_admin_config.yaml
  # 下载管理员service文件
  wget -O xray_admin.service https://raw.githubusercontent.com/gongshen/dino/main/resource/xray_admin.service && mv -f xray_admin.service ${xray_admin_service_dir}
  systemctl daemon-reload
  systemctl enable xray_admin
  systemctl restart xray_admin
  judge "xray_admin 启动"
}

function init_admin_db() {
  read -rp "请输入数据库类型(默认：mysql)：" ADMIN_DB_TYPE
  [ -z "$ADMIN_DB_TYPE" ] && ADMIN_DB_TYPE="mysql"
  read -rp "请输入数据库地址(默认：127.0.0.1)：" ADMIN_DB_HOST
  [ -z "$ADMIN_DB_HOST" ] && ADMIN_DB_HOST="127.0.0.1"
  read -rp "请输入数据库端口(默认：3306)：" ADMIN_DB_PORT
  [ -z "$ADMIN_DB_PORT" ] && ADMIN_DB_PORT= "3306"
  read -rp "请输入数据库用户名(默认：root)：" ADMIN_DB_USERNAME
  [ -z "$ADMIN_DB_USERNAME" ] && ADMIN_DB_USERNAME="root"
  read -rp "请输入数据库密码(默认：123456)：" ADMIN_DB_PASSWORD
  [ -z "$ADMIN_DB_PASSWORD" ] && ADMIN_DB_PASSWORD="123456"
  read -rp "请输入数据库库名(默认：gva)：" ADMIN_DB_NAME
  [ -z "$ADMIN_DB_NAME" ] && ADMIN_DB_NAME="gva"
  headers='Content-Type: application/json'
  data="{\"dbType\": \"$ADMIN_DB_TYPE\",\"host\": \"$ADMIN_DB_HOST\",\"port\": \"$ADMIN_DB_PORT\", \"userName\": \"$ADMIN_DB_USERNAME\", \"password\": \"$ADMIN_DB_PASSWORD\", \"dbName\": \"$ADMIN_DB_NAME\"}"
  curl -X POST -H "$headers" -d "$data" http://127.0.0.1:8888/init/initdb
}

function install_xray() {
  is_root
  system_check
  dependency_install
  basic_optimization
  xray_install
}

menu() {
  echo -e "\t Xray 安装管理脚本 ${Red}${Font}"
  echo -e "—————————————— 安装向导 ——————————————"""
  echo -e "${Green}2.${Font}  安装 Xray"
  echo -e "${Green}3.${Font}  配置 Xray (VMESS + TCP[http伪装])"
  echo -e "${Green}4.${Font} 查看 实时访问日志"
  echo -e "${Green}5.${Font} 查看 实时错误日志"
  echo -e "${Green}6.${Font} 查看 Xray 配置链接"
  echo -e "—————————————— 其他选项 ——————————————"
  echo -e "${Green}7.${Font} 安装 4 合 1 BBR、锐速安装脚本"
  echo -e "${Green}8.${Font} 卸载 Xray"
  echo -e "${Green}9.${Font} 更新 Xray-core"
  echo -e "${Green}11.${Font} 安装stat"
  echo -e "${Green}12.${Font} 安装管理端程序"
  echo -e "${Green}13.${Font} 安装mysql"
  echo -e "${Green}14.${Font} 初始化管理端数据库"
  echo -e "${Green}15.${Font} 配置iptables"
  echo -e "${Green}40.${Font} 退出"
  read -rp "请输入数字：" menu_num
  case $menu_num in
  2)
    install_xray
    ;;
  3)
    configure_xray
    ;;
  4)
    tail -f $xray_access_log
    ;;
  5)
    tail -f $xray_error_log
    ;;
  6)
    if [[ -f $xray_conf_dir/config.json ]]; then
      basic_information
    else
      print_error "xray 配置文件不存在"
    fi
    ;;
  7)
    bbr_boost_sh
    ;;
  8)
    source '/etc/os-release'
    xray_uninstall
    ;;
  9)
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" - install
    restart_all
    ;;
  11)
    install_stat
    ;;
  12)
    install_admin
    ;;
  13)
    install_mysql
    ;;
  14)
    init_admin_db
    ;;
  15)
    config_iptables
    ;;
  40)
    exit 0
    ;;
  *)
    print_error "请输入正确的数字"
    ;;
  esac
}
menu "$@"