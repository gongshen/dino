#!/usr/bin/env bash

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