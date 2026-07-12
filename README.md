# Realm 转发面板安装器

这是给 NAT VPS 使用的一键安装脚本，会安装：

- Realm 转发内核
- 带 Basic Auth 登录的简易 Web 面板
- systemd 自启服务
- 一条默认转发规则

## 交互式安装

在 NAT VPS 上用 root 执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/install.sh)
```

脚本会用中文询问：

- Web 面板内部端口
- 转发内部监听端口
- 转发目标地址/IP
- 转发目标端口
- Web 面板公网端口（仅用于安装完成提示）
- 转发公网端口（仅用于安装完成提示）

直接回车使用默认值。

## 一行命令默认安装

如果 NAT 面板映射如下：

- 外部 `50001` -> 内部 `50002`，用于 Web 面板
- 外部 `33507` -> 内部 `33507`，用于转发

在 VPS 上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/install.sh) --public-panel-port 50001 --public-forward-port 33507
```

默认规则：

```text
0.0.0.0:33507 -> www.mokuoha.com:33507
```

## 自定义非交互安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/install.sh) \
  --panel-port 50002 \
  --listen-port 33507 \
  --remote-host www.mokuoha.com \
  --remote-port 33507 \
  --public-panel-port 50001 \
  --public-forward-port 33507
```

## 常用管理命令

```bash
systemctl status realm
systemctl status realm-panel
journalctl -u realm -f
journalctl -u realm-panel -f
```
