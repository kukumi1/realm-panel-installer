# Realm 转发面板安装器

这是给 NAT VPS 使用的一键安装脚本，会安装：

- Realm 转发内核
- 带 Basic Auth 登录的简易 Web 面板
- systemd 自启服务
- 一条默认转发规则

## 安全说明

Web 面板默认只监听 `127.0.0.1`，不对公网开放，通过 SSH 隧道访问（见下文）。

- 面板密码以 PBKDF2-SHA256 加盐哈希存储，配置文件里不保存明文。
- Basic Auth 使用常量时间比较，并对失败登录做限速。
- 如需公网直连（不推荐，仅 Basic Auth + 明文 HTTP），可传 `--panel-bind 0.0.0.0`。

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

## 访问 Web 面板（SSH 隧道）

面板默认只听本机，从你的电脑建立 SSH 隧道后用浏览器访问：

```bash
ssh -L 8080:127.0.0.1:50002 root@<VPS地址>
```

然后浏览器打开 `http://127.0.0.1:8080`，用安装完成时显示的用户名/密码登录。

其中 `50002` 是面板内部端口（`--panel-port`），`8080` 是本地任意空闲端口。

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

如需面板对公网开放（不推荐）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/install.sh) --panel-bind 0.0.0.0
```

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/uninstall.sh)
```

会停止并移除 realm、realm-panel 服务及相关文件。

## 全部参数

```text
--panel-port PORT          Web 面板内部端口。默认: 50002
--listen-port PORT         Realm 内部监听端口。默认: 33507
--remote-host HOST         转发目标地址。默认: www.mokuoha.com
--remote-port PORT         转发目标端口。默认: 33507
--panel-user USER          Web 面板用户名。默认: admin
--panel-password PASS      Web 面板密码。默认: 随机生成
--panel-bind ADDR          Web 面板监听地址。默认: 127.0.0.1
--realm-version TAG        Realm 版本。默认: v2.9.4
--public-panel-port PORT   仅用于安装完成提示显示公网面板端口
--public-forward-port PORT 仅用于安装完成提示显示公网转发端口
-h, --help                 显示帮助
```

面板密码以 PBKDF2-SHA256 哈希存储，不保存明文。内置 v2.9.4 的 sha256 校验值；换用其它版本会跳过完整性校验并给出提示。

## Web 面板功能

- 新增 / 编辑 / 删除转发规则
- 逐规则 UDP 开关
- 规则备注
- 查看 realm 运行状态与日志

## 常用管理命令

```bash
systemctl status realm
systemctl status realm-panel
journalctl -u realm -f
journalctl -u realm-panel -f
```

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/uninstall.sh)
```

会停用并删除两个服务、清理 `/opt/realm`、`/opt/realm-panel`、`/etc/realm`、`/etc/realm-panel`。
