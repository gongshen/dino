# base
> 安装xray需要的杂七杂八集合

### xray版本：v25.3.6

### 额外信息
- [增加pprof](https://github.com/XTLS/Xray-core/pull/1000)
- [流量统计官网配置介绍](https://xtls.github.io/config/stats.html#statsobject)
- [流量统计踩坑](https://bytemeta.vip/repo/XTLS/Xray-core/issues/687)

### 安装xray
```shell
wget -N --no-check-certificate -q -O install.sh "https://raw.githubusercontent.com/gongshen/dino/main/resource/install.sh" && chmod +x install.sh && bash install.sh
```

### 注意事项：
1. VMESS没有fallback的功能
2. 使用Xray25.3.6版本
3. mysql8.0版本
4. ssh强制启用传统算法: ssh -o PubkeyAcceptedAlgorithms=+ssh-rsa