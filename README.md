# 多后端转发面板安装器

给 NAT VPS 使用的一键安装脚本，安装一个带登录认证的中文 Web 面板，统一管理四种转发后端：

- **Realm** — 单进程多规则，TCP/UDP 转发内核
- **socat** — 每条规则独立 systemd 单元，通用性强
- **GOST v3** — 单进程多规则，功能丰富
- **nftables（内核）** — 内核态 DNAT 转发，无用户态进程开销；目标为域名时由定时任务自动重解析刷新

面板把所有规则存在统一的 `rules.json`，按每条规则选择的后端分发落地。nftables 后端使用独立的 `realmpanel` 表，与系统及 Docker 规则隔离，卸载时精确清理不影响其它防火墙规则。

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

脚本会用中文询问面板端口等配置，直接回车使用默认值。安装会装好 realm、gost、socat、nftables 四种后端，但**不创建任何预置转发规则**，所有转发规则请安装后在 Web 面板中自行添加。

## 访问 Web 面板（SSH 隧道）

面板默认只听本机，从你的电脑建立 SSH 隧道后用浏览器访问：

```bash
ssh -L 8080:127.0.0.1:50002 root@<VPS地址>
```

然后浏览器打开 `http://127.0.0.1:8080`，用安装完成时显示的用户名/密码登录。

其中 `50002` 是面板内部端口（`--panel-port`），`8080` 是本地任意空闲端口。

## 一行命令默认安装

如果 NAT 面板把外部 `50001` 映射到内部 `50002`（Web 面板），在 VPS 上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/install.sh) --public-panel-port 50001
```

转发端口的 NAT 映射请按你在面板中添加的规则自行在 VPS 服务商处配置。

## Web 面板功能

- 新增 / 编辑 / 删除转发规则（安装后面板为空，规则全部在此添加）
- 每条规则选择后端：realm / socat / GOST / nftables
- 逐规则 UDP 开关
- 规则备注
- 查看 realm、GOST 运行状态与日志

在面板里切换某条规则的后端时，旧后端的配置/服务会自动清理，新后端立即接管。

## 全部参数

```text
--panel-port PORT          Web 面板内部端口。默认: 50002
--panel-user USER          Web 面板用户名。默认: admin
--panel-password PASS      Web 面板密码。默认: 随机生成
--panel-bind ADDR          Web 面板监听地址。默认: 127.0.0.1
--realm-version TAG        Realm 版本。默认: v2.9.4
--gost-version TAG         GOST 版本。默认: v3.2.6
--public-panel-port PORT   仅用于安装完成提示显示公网面板端口
-h, --help                 显示帮助
```

内置 realm v2.9.4 与 gost v3.2.6 的 sha256 校验值；换用其它版本会跳过完整性校验并给出提示。

## 常用管理命令

```bash
systemctl status realm-panel
systemctl status realm
systemctl status gost
journalctl -u realm-panel -f
```

socat 规则以 `rp-socat-<规则ID>-tcp/udp.service` 命名的动态单元运行。

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kukumi1/realm-panel-installer/main/uninstall.sh)
```

会停用并删除 realm、gost、realm-panel 服务及所有 socat 动态单元，清理 `/opt` 下的程序文件。加 `--purge` 一并删除 `/etc/realm`、`/etc/gost`、`/etc/realm-panel` 配置目录。
