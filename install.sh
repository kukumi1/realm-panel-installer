#!/usr/bin/env bash
set -Eeuo pipefail

REALM_VERSION="v2.9.4"
GOST_VERSION="v3.2.6"
PANEL_PORT="50002"
LISTEN_PORT="33507"
REMOTE_HOST="www.mokuoha.com"
REMOTE_PORT="33507"
PANEL_USER="admin"
PANEL_PASSWORD=""
PANEL_BIND="127.0.0.1"
PUBLIC_PANEL_PORT=""
PUBLIC_FORWARD_PORT=""
INSTALL_DIR="/opt/realm-panel"
PANEL_CONFIG_DIR="/etc/realm-panel"
REALM_DIR="/opt/realm"
REALM_CONFIG_DIR="/etc/realm"
GOST_DIR="/opt/gost"
GOST_CONFIG_DIR="/etc/gost"
PANEL_PORT_SET=0
LISTEN_PORT_SET=0
REMOTE_HOST_SET=0
REMOTE_PORT_SET=0
PUBLIC_PANEL_PORT_SET=0
PUBLIC_FORWARD_PORT_SET=0

usage() {
  cat <<'EOF'
Usage:
  bash install.sh [options]

如果在交互式终端运行，缺少的配置会逐项询问。
直接回车使用括号里的默认值。

参数:
  --panel-port PORT          Web 面板内部端口。默认: 50002
  --listen-port PORT         Realm 内部监听端口。默认: 33507
  --remote-host HOST         转发目标地址。默认: www.mokuoha.com
  --remote-port PORT         转发目标端口。默认: 33507
  --panel-user USER          Web 面板用户名。默认: admin
  --panel-password PASS      Web 面板密码。默认: 随机生成
  --panel-bind ADDR          Web 面板监听地址。默认: 127.0.0.1（仅本机，
                             通过 SSH 隧道访问）。如需公网直连传 0.0.0.0。
  --realm-version VER        Realm 版本。默认: v2.9.4。切换到非内置版本时
                             会跳过 sha256 校验并给出告警。
  --gost-version VER         GOST 版本。默认: v3.2.6。切换到非内置版本时
                             会跳过 sha256 校验并给出告警。
  --public-panel-port PORT   可选，仅用于最终提示显示公网面板端口。
  --public-forward-port PORT 可选，仅用于最终提示显示公网转发端口。
  -h, --help                 显示帮助。

示例:
  bash install.sh --public-panel-port 50001 --public-forward-port 33507
  bash install.sh --panel-port 51006 --listen-port 21003 --remote-host 85.149.211.29 --remote-port 21003
  bash install.sh --panel-bind 0.0.0.0   # 公网直连（不推荐，仅 Basic Auth）
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --panel-port) PANEL_PORT="${2:?}"; PANEL_PORT_SET=1; shift 2 ;;
    --listen-port) LISTEN_PORT="${2:?}"; LISTEN_PORT_SET=1; shift 2 ;;
    --remote-host) REMOTE_HOST="${2:?}"; REMOTE_HOST_SET=1; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:?}"; REMOTE_PORT_SET=1; shift 2 ;;
    --panel-user) PANEL_USER="${2:?}"; shift 2 ;;
    --panel-password) PANEL_PASSWORD="${2:?}"; shift 2 ;;
    --panel-bind) PANEL_BIND="${2:?}"; shift 2 ;;
    --realm-version) REALM_VERSION="${2:?}"; shift 2 ;;
    --gost-version) GOST_VERSION="${2:?}"; shift 2 ;;
    --public-panel-port) PUBLIC_PANEL_PORT="${2:?}"; PUBLIC_PANEL_PORT_SET=1; shift 2 ;;
    --public-forward-port) PUBLIC_FORWARD_PORT="${2:?}"; PUBLIC_FORWARD_PORT_SET=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "未知参数: $1" ;;
  esac
done

prompt_value() {
  local label=$1
  local current=$2
  local answer
  printf '%s [%s]: ' "$label" "$current" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  if [[ -n "$answer" ]]; then
    printf '%s' "$answer"
  else
    printf '%s' "$current"
  fi
}

prompt_config() {
  [[ -t 0 && -r /dev/tty ]] || return 0
  echo "交互式配置：直接回车使用默认值。" > /dev/tty
  if [[ $PANEL_PORT_SET -eq 0 ]]; then
    PANEL_PORT="$(prompt_value 'Web 面板内部端口' "$PANEL_PORT")"
  fi
  if [[ $LISTEN_PORT_SET -eq 0 ]]; then
    LISTEN_PORT="$(prompt_value '转发内部监听端口' "$LISTEN_PORT")"
  fi
  if [[ $REMOTE_HOST_SET -eq 0 ]]; then
    REMOTE_HOST="$(prompt_value '转发目标地址/IP' "$REMOTE_HOST")"
  fi
  if [[ $REMOTE_PORT_SET -eq 0 ]]; then
    REMOTE_PORT="$(prompt_value '转发目标端口' "$REMOTE_PORT")"
  fi
  if [[ $PUBLIC_PANEL_PORT_SET -eq 0 ]]; then
    PUBLIC_PANEL_PORT="$(prompt_value 'Web 面板公网端口（仅用于安装完成提示）' "${PUBLIC_PANEL_PORT:-$PANEL_PORT}")"
  fi
  if [[ $PUBLIC_FORWARD_PORT_SET -eq 0 ]]; then
    PUBLIC_FORWARD_PORT="$(prompt_value '转发公网端口（仅用于安装完成提示）' "${PUBLIC_FORWARD_PORT:-$LISTEN_PORT}")"
  fi
}

prompt_config

[[ $EUID -eq 0 ]] || fail "请使用 root 用户运行。"
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || fail "--panel-port 无效"
[[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || fail "--listen-port 无效"
[[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] || fail "--remote-port 无效"
[[ "$PANEL_BIND" =~ ^[0-9A-Fa-f.:]+$ ]] || fail "--panel-bind 无效"
[[ "$REALM_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--realm-version 无效（形如 v2.9.4）"
[[ "$GOST_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "--gost-version 无效（形如 v3.2.6）"

if [[ -z "$PANEL_PASSWORD" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    PANEL_PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 18)"
  else
    PANEL_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18)"
  fi
fi

install_packages() {
  local need_install=0
  command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 && command -v socat >/dev/null 2>&1 || need_install=1
  [[ $need_install -eq 0 ]] && return 0
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update || warn "apt-get update 失败，可能是某个软件源失效；继续尝试安装依赖。"
    apt-get install -y curl tar python3 ca-certificates socat nftables
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl tar python3 ca-certificates socat nftables
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl tar python3 ca-certificates socat nftables
  else
    fail "未找到支持的包管理器，请手动安装 curl、tar、python3、ca-certificates、socat、nftables。"
  fi
}

check_port_free() {
  local port=$1 label=$2
  command -v ss >/dev/null 2>&1 || return 0
  if ss -Hltn "sport = :${port}" 2>/dev/null | grep -q .; then
    fail "${label}端口 ${port} 已被占用，请换一个端口或先停用占用进程。"
  fi
}

realm_asset() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) printf 'realm-x86_64-unknown-linux-gnu.tar.gz' ;;
    aarch64|arm64) printf 'realm-aarch64-unknown-linux-gnu.tar.gz' ;;
    *) fail "不支持的系统架构: $arch" ;;
  esac
}

expected_digest() {
  [[ "$REALM_VERSION" == "v2.9.4" ]] || { printf ''; return 0; }
  case "$1" in
    realm-x86_64-unknown-linux-gnu.tar.gz) printf '9dec109386b8abc828b452d0d1cecde35b7a2f8cfa93eae757fe9c248ad07ddd' ;;
    realm-aarch64-unknown-linux-gnu.tar.gz) printf '1f7f06e82fe0ea798b5c8e8e32906ee212a7085629a1c5cef9957ca270fcad99' ;;
    *) printf '' ;;
  esac
}

verify_digest() {
  local file=$1 expected=$2 actual
  if ! command -v sha256sum >/dev/null 2>&1; then
    warn "未找到 sha256sum，跳过完整性校验。"; return 0
  fi
  [[ -n "$expected" ]] || { warn "无该架构的内置校验值（Realm ${REALM_VERSION}），跳过完整性校验。"; return 0; }
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "Realm 下载文件校验失败：期望 ${expected}，实际 ${actual}。文件可能损坏或被篡改。"
  log "Realm 下载文件 sha256 校验通过。"
}

install_realm() {
  local asset url tmp
  asset="$(realm_asset)"
  url="https://github.com/zhboner/realm/releases/download/${REALM_VERSION}/${asset}"
  tmp="/tmp/${asset}.$$"
  mkdir -p "$REALM_DIR" "$REALM_CONFIG_DIR"
  log "正在下载 Realm ${REALM_VERSION} (${asset})"
  curl -fsSL -o "$tmp" "$url"
  verify_digest "$tmp" "$(expected_digest "$asset")"
  tar -xzf "$tmp" -C "$REALM_DIR" realm
  rm -f "$tmp"
  chmod 0755 "$REALM_DIR/realm"
}

gost_asset() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) printf 'gost_%s_linux_amd64.tar.gz' "${GOST_VERSION#v}" ;;
    aarch64|arm64) printf 'gost_%s_linux_arm64.tar.gz' "${GOST_VERSION#v}" ;;
    *) fail "GOST 不支持的系统架构: $arch" ;;
  esac
}

gost_digest() {
  [[ "$GOST_VERSION" == "v3.2.6" ]] || { printf ''; return 0; }
  case "$1" in
    gost_3.2.6_linux_amd64.tar.gz) printf 'b39037b0380ea001fb3c0c28441c2e10bfc694f90682739a65b53e55dce5238b' ;;
    gost_3.2.6_linux_arm64.tar.gz) printf 'f674c8f4a033dc1dfd4f0d5e9602fbe5b0d0f81307bf3794f44b5b5d6d622eae' ;;
    *) printf '' ;;
  esac
}

verify_gost_digest() {
  local file=$1 expected=$2 actual
  if ! command -v sha256sum >/dev/null 2>&1; then
    warn "未找到 sha256sum，跳过 GOST 完整性校验。"; return 0
  fi
  [[ -n "$expected" ]] || { warn "无该架构的内置校验值（GOST ${GOST_VERSION}），跳过完整性校验。"; return 0; }
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "GOST 下载文件校验失败：期望 ${expected}，实际 ${actual}。文件可能损坏或被篡改。"
  log "GOST 下载文件 sha256 校验通过。"
}

install_gost() {
  local asset url tmp
  asset="$(gost_asset)"
  url="https://github.com/go-gost/gost/releases/download/${GOST_VERSION}/${asset}"
  tmp="/tmp/${asset}.$$"
  mkdir -p "$GOST_DIR" "$GOST_CONFIG_DIR"
  log "正在下载 GOST ${GOST_VERSION} (${asset})"
  curl -fsSL -o "$tmp" "$url"
  verify_gost_digest "$tmp" "$(gost_digest "$asset")"
  tar -xzf "$tmp" -C "$GOST_DIR" gost
  rm -f "$tmp"
  chmod 0755 "$GOST_DIR/gost"
}

install_socat() {
  command -v socat >/dev/null 2>&1 && return 0
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y socat || warn "socat 安装失败，socat 后端将不可用。"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y socat || warn "socat 安装失败，socat 后端将不可用。"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y socat || warn "socat 安装失败，socat 后端将不可用。"
  else
    warn "未找到包管理器，socat 后端将不可用。"
  fi
}

write_gost_service() {
  cat > /etc/systemd/system/gost.service <<EOF
[Unit]
Description=GOST v3 Forwarding Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${GOST_DIR}/gost -C ${GOST_CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  echo '{"services": []}' > "$GOST_CONFIG_DIR/config.json"
}

write_initial_rules() {
  mkdir -p "$PANEL_CONFIG_DIR"
  [[ -f "$PANEL_CONFIG_DIR/rules.json" ]] && return 0
  local id
  id="$(tr -dc 'a-f0-9' </dev/urandom | head -c 8)"
  cat > "$PANEL_CONFIG_DIR/rules.json" <<EOF
[
  {
    "id": "${id}",
    "backend": "realm",
    "listen_port": ${LISTEN_PORT},
    "remote_host": "${REMOTE_HOST}",
    "remote_port": ${REMOTE_PORT},
    "udp": true,
    "note": "",
    "enabled": true
  }
]
EOF
}

write_realm_service() {
  cat > /etc/systemd/system/realm.service <<'EOF'
[Unit]
Description=Realm TCP/UDP Forwarding Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/realm
ExecStart=/opt/realm/realm -c /etc/realm/config.toml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

write_panel() {
  mkdir -p "$INSTALL_DIR" "$PANEL_CONFIG_DIR"
  PANEL_USER="$PANEL_USER" PANEL_PASSWORD="$PANEL_PASSWORD" python3 - "$PANEL_CONFIG_DIR/config.json" <<'PYHASH'
import hashlib, json, os, sys, secrets
user = os.environ["PANEL_USER"]
password = os.environ["PANEL_PASSWORD"]
salt = secrets.token_bytes(16)
iterations = 200000
digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, iterations)
config = {
    "username": user,
    "algorithm": "pbkdf2_sha256",
    "iterations": iterations,
    "salt": salt.hex(),
    "hash": digest.hex(),
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(config, f)
PYHASH
  chmod 0600 "$PANEL_CONFIG_DIR/config.json"
  cat > "$INSTALL_DIR/panel.py" <<'PYEOF'
#!/usr/bin/env python3
import base64, hashlib, hmac, html, json, os, re, secrets, socket, subprocess, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

PANEL_CONFIG = "/etc/realm-panel/config.json"
RULES_PATH = "/etc/realm-panel/rules.json"
REALM_CONFIG = "/etc/realm/config.toml"
GOST_CONFIG = "/etc/gost/config.json"
UNIT_DIR = "/etc/systemd/system"
NFT_TABLE = "realmpanel"
LISTEN_HOST = os.environ.get("REALM_PANEL_BIND", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("REALM_PANEL_PORT", "50002"))
BACKENDS = ("realm", "socat", "gost", "nftables")
BACKEND_LABEL = {"realm": "Realm", "socat": "socat", "gost": "GOST", "nftables": "nftables (内核)"}
FAILED_ATTEMPTS = {}
FAILED_LOCK = threading.Lock()
RULES_LOCK = threading.Lock()
MAX_ATTEMPTS = 10
WINDOW_SECONDS = 300
HOST_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,253}$")
REALM_BASE_CONFIG = """[log]
level = "info"
output = "stdout"

[network]
use_udp = true
tcp_timeout = 10
udp_timeout = 30
tcp_keepalive = 60
""".strip() + "\n"


def run(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60)
    return proc.returncode, proc.stdout.strip()


def load_rules():
    if not os.path.exists(RULES_PATH):
        return []
    try:
        with open(RULES_PATH, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_rules(rules):
    tmp = RULES_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rules, f, ensure_ascii=False, indent=2)
    os.replace(tmp, RULES_PATH)


def new_rule_id():
    return secrets.token_hex(4)


def validate_port(value):
    port = int(value)
    if port < 1 or port > 65535:
        raise ValueError("端口必须在 1 到 65535 之间")
    return port


def validate_host(host):
    if not HOST_RE.match(host):
        raise ValueError("目标地址不合法")
    return host


def validate_note(value):
    value = value.strip()
    if len(value) > 40:
        raise ValueError("备注不能超过 40 个字符")
    if any(ord(c) < 32 for c in value):
        raise ValueError("备注含非法字符")
    return value


def validate_backend(value):
    if value not in BACKENDS:
        raise ValueError("未知转发后端")
    return value


def rule_from_form(form):
    rule = {
        "backend": validate_backend(form.get("backend", [""])[0]),
        "listen_port": validate_port(form.get("listen_port", [""])[0]),
        "remote_host": validate_host(form.get("remote_host", [""])[0].strip()),
        "remote_port": validate_port(form.get("remote_port", [""])[0]),
        "udp": "1" in form.get("udp", []),
        "note": validate_note(form.get("note", [""])[0]),
        "enabled": True,
    }
    if rule["backend"] == "nftables":
        rule["resolved_ip"] = rule["remote_host"] if IPV4_RE.match(rule["remote_host"]) else resolve_v4(rule["remote_host"])
    return rule


def ensure_no_port_conflict(rules, listen_port, skip_id=None):
    for r in rules:
        if r["id"] != skip_id and r["listen_port"] == listen_port:
            raise ValueError("监听端口 %d 已被其它规则占用" % listen_port)


def resolve_v4(host):
    try:
        infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
    except Exception:
        return None
    return infos[0][4][0] if infos else None


IPV4_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")


def apply_realm(rules):
    active = [r for r in rules if r["backend"] == "realm" and r.get("enabled", True)]
    if not active:
        run(["systemctl", "stop", "realm"])
        return
    tmp = REALM_CONFIG + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(REALM_BASE_CONFIG)
        for r in active:
            f.write("\n[[endpoints]]\n")
            f.write('listen = "0.0.0.0:%d"\n' % r["listen_port"])
            f.write('remote = "%s:%d"\n' % (r["remote_host"], r["remote_port"]))
            f.write("network = { use_udp = %s }\n" % ("true" if r.get("udp", True) else "false"))
    os.replace(tmp, REALM_CONFIG)
    run(["systemctl", "enable", "realm"])
    run(["systemctl", "restart", "realm"])


def socat_units_for(rule):
    names = ["rp-socat-%s-tcp.service" % rule["id"]]
    if rule.get("udp", True):
        names.append("rp-socat-%s-udp.service" % rule["id"])
    return names


def write_socat_unit(path, proto, rule):
    listen = "%s4-LISTEN:%d,reuseaddr,fork" % (proto.upper(), rule["listen_port"])
    target = "%s4:%s:%d" % (proto.upper(), rule["remote_host"], rule["remote_port"])
    unit = """[Unit]
Description=realm-panel socat %s %d
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/socat %s %s
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
""" % (proto, rule["listen_port"], listen, target)
    with open(path, "w", encoding="utf-8") as f:
        f.write(unit)


def existing_socat_units():
    if not os.path.isdir(UNIT_DIR):
        return []
    return [fn for fn in os.listdir(UNIT_DIR) if fn.startswith("rp-socat-") and fn.endswith(".service")]


def apply_socat(rules):
    active = [r for r in rules if r["backend"] == "socat" and r.get("enabled", True)]
    wanted = {}
    for r in active:
        for proto, name in zip(("tcp", "udp"), socat_units_for(r)):
            wanted[name] = (proto, r)
    existing = set(existing_socat_units())
    for unit in existing - set(wanted):
        run(["systemctl", "disable", "--now", unit])
        try:
            os.remove(os.path.join(UNIT_DIR, unit))
        except OSError:
            pass
    for name, (proto, r) in wanted.items():
        write_socat_unit(os.path.join(UNIT_DIR, name), proto, r)
    run(["systemctl", "daemon-reload"])
    for name in wanted:
        run(["systemctl", "enable", name])
        run(["systemctl", "restart", name])


def apply_gost(rules):
    active = [r for r in rules if r["backend"] == "gost" and r.get("enabled", True)]
    if not active:
        run(["systemctl", "stop", "gost"])
        return
    services = []
    for r in active:
        protos = ["tcp"] + (["udp"] if r.get("udp", True) else [])
        for proto in protos:
            services.append({
                "name": "rule-%s-%s" % (r["id"], proto),
                "addr": ":%d" % r["listen_port"],
                "handler": {"type": proto},
                "listener": {"type": proto},
                "forwarder": {"nodes": [
                    {"name": "target", "addr": "%s:%d" % (r["remote_host"], r["remote_port"])}
                ]},
            })
    tmp = GOST_CONFIG + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"services": services}, f, ensure_ascii=False, indent=2)
    os.replace(tmp, GOST_CONFIG)
    run(["systemctl", "enable", "gost"])
    run(["systemctl", "restart", "gost"])


def nft_target_ip(rule):
    host = rule["remote_host"]
    if IPV4_RE.match(host):
        return host
    resolved = resolve_v4(host)
    if resolved:
        rule["resolved_ip"] = resolved
        return resolved
    return rule.get("resolved_ip")


def build_nft_ruleset(active):
    lines = ["add table ip realmpanel",
             "flush table ip realmpanel",
             "add chain ip realmpanel prerouting { type nat hook prerouting priority dstnat; policy accept; }",
             "add chain ip realmpanel postrouting { type nat hook postrouting priority srcnat; policy accept; }"]
    for r in active:
        ip = nft_target_ip(r)
        if not ip:
            continue
        lport, rport = r["listen_port"], r["remote_port"]
        protos = ["tcp"] + (["udp"] if r.get("udp", True) else [])
        for proto in protos:
            lines.append('add rule ip realmpanel prerouting %s dport %d dnat to %s:%d comment "rp:%s:%s"'
                         % (proto, lport, ip, rport, r["id"], proto))
            lines.append('add rule ip realmpanel postrouting ip daddr %s %s dport %d masquerade comment "rp:%s:%s"'
                         % (ip, proto, rport, r["id"], proto))
    return "\n".join(lines) + "\n"


def forward_accept_ports(active):
    return sorted({r["listen_port"] for r in active})


def apply_forward_accept(active):
    run(["iptables", "-N", "REALM_PANEL_FWD"])
    run(["iptables", "-F", "REALM_PANEL_FWD"])
    _, out = run(["iptables", "-S", "DOCKER-USER"])
    hook_chain = "DOCKER-USER" if out and "-N DOCKER-USER" in out else "FORWARD"
    run(["iptables", "-D", hook_chain, "-j", "REALM_PANEL_FWD"])
    if active:
        run(["iptables", "-I", hook_chain, "1", "-j", "REALM_PANEL_FWD"])
        run(["iptables", "-A", "REALM_PANEL_FWD", "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"])
        for r in active:
            ip = r.get("resolved_ip") or (r["remote_host"] if IPV4_RE.match(r["remote_host"]) else None)
            if not ip:
                continue
            for proto in ["tcp"] + (["udp"] if r.get("udp", True) else []):
                run(["iptables", "-A", "REALM_PANEL_FWD", "-p", proto, "-d", ip,
                     "--dport", str(r["remote_port"]), "-j", "ACCEPT"])


def apply_nft(rules):
    active = [r for r in rules if r["backend"] == "nftables" and r.get("enabled", True)]
    if not active:
        run(["nft", "delete", "table", "ip", "realmpanel"])
        apply_forward_accept([])
        return
    ruleset = build_nft_ruleset(active)
    proc = subprocess.run(["nft", "-f", "-"], input=ruleset, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, timeout=30)
    if proc.returncode != 0:
        raise ValueError("nftables 规则应用失败：%s" % proc.stdout.strip())
    apply_forward_accept(active)


def apply_all(rules):
    apply_realm(rules)
    apply_socat(rules)
    apply_gost(rules)
    apply_nft(rules)


def verify_credentials(username, password):
    cfg = json.load(open(PANEL_CONFIG, encoding="utf-8"))
    if not hmac.compare_digest(username, cfg["username"]):
        return False
    salt = bytes.fromhex(cfg["salt"])
    expected = bytes.fromhex(cfg["hash"])
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, cfg["iterations"])
    return hmac.compare_digest(digest, expected)


def rate_limited(key):
    now = time.time()
    with FAILED_LOCK:
        hits = [t for t in FAILED_ATTEMPTS.get(key, []) if now - t < WINDOW_SECONDS]
        FAILED_ATTEMPTS[key] = hits
        return len(hits) >= MAX_ATTEMPTS


def record_failure(key):
    with FAILED_LOCK:
        FAILED_ATTEMPTS.setdefault(key, []).append(time.time())


PAGE_CSS = "body{font-family:system-ui,-apple-system,Segoe UI,sans-serif;margin:0;background:#f6f7f9;color:#14181f}main{max-width:1040px;margin:32px auto;padding:0 18px}section,.top{background:#fff;border:1px solid #e3e7ee;border-radius:8px;padding:20px;margin:16px 0}.top{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:12px}h1{margin:0;font-size:26px}h2{margin-top:0;font-size:18px}table{width:100%;border-collapse:collapse}th,td{padding:11px;border-bottom:1px solid #edf0f5;text-align:left;font-size:14px}input,select{display:block;margin-top:6px;padding:10px;border:1px solid #cbd3df;border-radius:6px;min-width:150px}button{padding:10px 14px;border:0;border-radius:6px;background:#155eef;color:#fff;font-weight:600;cursor:pointer}button.danger{background:#d92d20}button.ghost{background:#eef2ff;color:#155eef}form.inline{display:inline}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;align-items:end}.check{display:flex;align-items:center;gap:8px}.check input{margin-top:0;min-width:auto}pre{white-space:pre-wrap;background:#101828;color:#e6edf7;padding:16px;border-radius:8px;overflow:auto}.error{color:#b42318;font-weight:700}a{color:#155eef;text-decoration:none}.badge{font-size:12px;padding:2px 8px;border-radius:99px;font-weight:600}.badge.on{background:#e7f6ec;color:#087443}.badge.off{background:#f2f4f7;color:#667085}.tag{font-size:12px;padding:2px 8px;border-radius:6px;background:#eef2ff;color:#3538cd;font-weight:600}.muted{color:#98a2b3}.actions{display:flex;gap:8px}.tablewrap{overflow-x:auto}"


class Handler(BaseHTTPRequestHandler):
    server_version = "RealmPanel/2.0"

    def log_message(self, fmt, *args):
        return

    def authorized(self):
        client = self.client_address[0]
        if rate_limited(client):
            return False
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            username, _, password = base64.b64decode(header[6:]).decode("utf-8").partition(":")
        except Exception:
            record_failure(client)
            return False
        if verify_credentials(username, password):
            return True
        record_failure(client)
        return False

    def require_auth(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="Realm Panel"')
        self.end_headers()

    def send_html(self, body, status=200):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def redirect(self, to="/"):
        self.send_response(303)
        self.send_header("Location", to)
        self.end_headers()

    def read_form(self):
        length = int(self.headers.get("Content-Length", "0"))
        return parse_qs(self.rfile.read(length).decode("utf-8"))

    def do_GET(self):
        if not self.authorized():
            return self.require_auth()
        if self.path.startswith("/logs"):
            unit = "realm"
            for name in ("realm", "gost", "realm-panel"):
                if self.path == "/logs?unit=" + name:
                    unit = name
            _, out = run(["journalctl", "-u", unit, "-n", "150", "--no-pager"])
            return self.page(pre="$ journalctl -u %s -n 150 --no-pager\n%s" % (unit, out))
        self.page(body=self.index_body())

    def backend_status(self):
        parts = []
        for name in ("realm", "gost"):
            _, active = run(["systemctl", "is-active", name])
            cls = "on" if active == "active" else "off"
            parts.append('<span class="badge %s">%s: %s</span>' % (cls, BACKEND_LABEL[name], html.escape(active)))
        code, _ = run(["nft", "list", "table", "ip", "realmpanel"])
        nft_on = code == 0
        parts.append('<span class="badge %s">nftables: %s</span>' % ("on" if nft_on else "off", "已加载" if nft_on else "无规则"))
        return " ".join(parts)

    def index_body(self):
        rules = load_rules()
        rows = []
        for idx, r in enumerate(rules):
            udp = '<span class="badge on">UDP</span>' if r.get("udp", True) else '<span class="badge off">仅 TCP</span>'
            note = html.escape(r.get("note", "")) or '<span class="muted">—</span>'
            state = '<span class="badge on">启用</span>' if r.get("enabled", True) else '<span class="badge off">停用</span>'
            rows.append(
                '<tr><td>%d</td><td><span class="tag">%s</span></td><td>0.0.0.0:%d</td><td>%s:%d</td><td>%s</td><td>%s</td><td>%s</td>'
                '<td class="actions">'
                '<form class="inline" method="post" action="/edit"><input type="hidden" name="id" value="%s"><button class="ghost">编辑</button></form>'
                '<form class="inline" method="post" action="/delete" onsubmit="return confirm(\'确认删除这条转发规则？\')"><input type="hidden" name="id" value="%s"><button class="danger">删除</button></form>'
                '</td></tr>'
                % (idx + 1, html.escape(BACKEND_LABEL.get(r["backend"], r["backend"])), r["listen_port"],
                   html.escape(r["remote_host"]), r["remote_port"], udp, note, state, html.escape(r["id"]), html.escape(r["id"]))
            )
        table = '<tr><td colspan="8" class="muted">暂无转发规则</td></tr>' if not rows else "".join(rows)
        options = "".join('<option value="%s">%s</option>' % (b, BACKEND_LABEL[b]) for b in BACKENDS)
        return (
            '<div class="top"><div><h1>转发面板</h1><p>%s</p></div>'
            '<div><a href="/logs?unit=realm">Realm 日志</a> · <a href="/logs?unit=gost">GOST 日志</a></div></div>'
            '<section id="add"><h2>新增转发</h2><form method="post" action="/add" class="grid">'
            '<label>转发后端<select name="backend">%s</select></label>'
            '<label>本地监听端口<input name="listen_port" placeholder="33507" required pattern="[0-9]+" inputmode="numeric"></label>'
            '<label>目标地址<input name="remote_host" placeholder="www.mokuoha.com" required></label>'
            '<label>目标端口<input name="remote_port" placeholder="33507" required pattern="[0-9]+" inputmode="numeric"></label>'
            '<label>备注（可选）<input name="note" maxlength="40" placeholder="用途说明"></label>'
            '<label class="check"><input type="checkbox" name="udp" value="1" checked>转发 UDP</label>'
            '<button>新增并应用</button></form></section>'
            '<section><h2>当前规则</h2><div class="tablewrap"><table><thead><tr>'
            '<th>#</th><th>后端</th><th>本地监听</th><th>转发目标</th><th>UDP</th><th>备注</th><th>状态</th><th>操作</th>'
            '</tr></thead><tbody>%s</tbody></table></div></section>'
            % (self.backend_status(), options, table)
        )

    def edit_body(self, rule_id):
        rules = load_rules()
        rule = next((r for r in rules if r["id"] == rule_id), None)
        if rule is None:
            raise ValueError("规则不存在")
        options = "".join(
            '<option value="%s"%s>%s</option>' % (b, " selected" if b == rule["backend"] else "", BACKEND_LABEL[b])
            for b in BACKENDS
        )
        checked = "checked" if rule.get("udp", True) else ""
        return (
            '<div class="top"><div><h1>编辑转发规则</h1></div><div><a href="/">返回</a></div></div>'
            '<section><form method="post" action="/update" class="grid">'
            '<input type="hidden" name="id" value="%s">'
            '<label>转发后端<select name="backend">%s</select></label>'
            '<label>本地监听端口<input name="listen_port" value="%d" required pattern="[0-9]+" inputmode="numeric"></label>'
            '<label>目标地址<input name="remote_host" value="%s" required></label>'
            '<label>目标端口<input name="remote_port" value="%d" required pattern="[0-9]+" inputmode="numeric"></label>'
            '<label>备注（可选）<input name="note" maxlength="40" value="%s"></label>'
            '<label class="check"><input type="checkbox" name="udp" value="1" %s>转发 UDP</label>'
            '<button>保存并应用</button></form></section>'
            % (html.escape(rule["id"]), options, rule["listen_port"], html.escape(rule["remote_host"]),
               rule["remote_port"], html.escape(rule.get("note", "")), checked)
        )

    def do_POST(self):
        if not self.authorized():
            return self.require_auth()
        form = self.read_form()
        try:
            if self.path == "/edit":
                return self.page(body=self.edit_body(form.get("id", [""])[0]))
            with RULES_LOCK:
                rules = load_rules()
                if self.path == "/add":
                    rule = rule_from_form(form)
                    ensure_no_port_conflict(rules, rule["listen_port"])
                    rule["id"] = new_rule_id()
                    rules.append(rule)
                    save_rules(rules)
                    apply_all(rules)
                elif self.path == "/update":
                    rule_id = form.get("id", [""])[0]
                    target = next((r for r in rules if r["id"] == rule_id), None)
                    if target is None:
                        raise ValueError("规则不存在")
                    rule = rule_from_form(form)
                    ensure_no_port_conflict(rules, rule["listen_port"], skip_id=rule_id)
                    rule["id"] = rule_id
                    rule["enabled"] = target.get("enabled", True)
                    rules[rules.index(target)] = rule
                    save_rules(rules)
                    apply_all(rules)
                elif self.path == "/delete":
                    rule_id = form.get("id", [""])[0]
                    rules = [r for r in rules if r["id"] != rule_id]
                    save_rules(rules)
                    apply_all(rules)
                else:
                    raise ValueError("未知操作")
            self.redirect()
        except Exception as exc:
            self.page(body='<p class="error">%s</p><p><a href="/">返回</a></p>' % html.escape(str(exc)), status=400)

    def page(self, body="", pre="", status=200):
        pre_html = "<pre>%s</pre>" % html.escape(pre) if pre else ""
        self.send_html(
            '<!doctype html><html><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>转发面板</title><style>%s</style></head><body><main>%s%s</main></body></html>'
            % (PAGE_CSS, body, pre_html),
            status,
        )


if __name__ == "__main__":
    try:
        apply_all(load_rules())
    except Exception:
        pass
    ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
PYEOF
  chmod 0755 "$INSTALL_DIR/panel.py"
  cat > "$INSTALL_DIR/ddns_refresh.py" <<'DDNSEOF'
#!/usr/bin/env python3
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import panel


def main():
    with panel.RULES_LOCK:
        rules = panel.load_rules()
        nft_rules = [r for r in rules if r["backend"] == "nftables" and r.get("enabled", True)]
        if not nft_rules:
            return
        changed = False
        for r in nft_rules:
            host = r["remote_host"]
            if panel.IPV4_RE.match(host):
                continue
            new_ip = panel.resolve_v4(host)
            if new_ip and new_ip != r.get("resolved_ip"):
                r["resolved_ip"] = new_ip
                changed = True
        panel.apply_nft(rules)
        if changed:
            panel.save_rules(rules)


if __name__ == "__main__":
    main()
DDNSEOF
  chmod 0755 "$INSTALL_DIR/ddns_refresh.py"
}

enable_ip_forward() {
  cat > /etc/sysctl.d/99-realm-panel-forward.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || warn "无法开启 ip_forward，nftables 后端转发可能不通。"
}

write_ddns_units() {
  cat > /etc/systemd/system/realm-panel-ddns.service <<EOF
[Unit]
Description=Realm Panel nftables DNS refresh and rule rebuild
After=network-online.target realm-panel.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/ddns_refresh.py

[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/realm-panel-ddns.timer <<'EOF'
[Unit]
Description=Realm Panel nftables DNS refresh timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

write_panel_service() {
  cat > /etc/systemd/system/realm-panel.service <<EOF
[Unit]
Description=Simple Realm Forwarding Web Panel
After=network-online.target realm.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
Environment=REALM_PANEL_PORT=${PANEL_PORT}
Environment=REALM_PANEL_BIND=${PANEL_BIND}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/panel.py
Restart=on-failure
RestartSec=3s
NoNewPrivileges=false
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

main() {
  check_port_free "$PANEL_PORT" "Web 面板"
  check_port_free "$LISTEN_PORT" "转发监听"
  install_packages
  install_realm
  install_gost
  write_initial_rules
  write_realm_service
  write_gost_service
  write_panel
  write_panel_service
  systemctl daemon-reload
  systemctl enable realm-panel
  systemctl restart realm-panel
  sleep 2
  systemctl is-active --quiet realm-panel || fail "realm-panel 启动失败"
  local ip
  ip="$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
  cat <<EOF

安装完成。

Web 面板:
  监听: ${PANEL_BIND}:${PANEL_PORT}
  用户名: ${PANEL_USER}
  密码: ${PANEL_PASSWORD}
EOF
  if [[ "$PANEL_BIND" == "127.0.0.1" || "$PANEL_BIND" == "localhost" ]]; then
    cat <<EOF
  访问方式: 面板仅监听本机，请用 SSH 隧道从本地访问：
    ssh -N -L ${PANEL_PORT}:127.0.0.1:${PANEL_PORT} root@${ip}
  然后浏览器打开 http://127.0.0.1:${PANEL_PORT}
EOF
  else
    cat <<EOF
  访问方式: http://${ip}:${PUBLIC_PANEL_PORT:-$PANEL_PORT}
  注意: 面板对公网开放，仅有 Basic Auth 明文保护，建议改用 127.0.0.1 + SSH 隧道。
EOF
  fi
  cat <<EOF

默认转发规则（Realm 后端）:
  公网入口: ${ip}:${PUBLIC_FORWARD_PORT:-$LISTEN_PORT}
  内部监听: 0.0.0.0:${LISTEN_PORT}
  目标: ${REMOTE_HOST}:${REMOTE_PORT}

支持的转发后端: Realm / socat / GOST（在面板中逐条选择）

服务:
  systemctl status realm-panel   # 面板本体
  systemctl status realm         # Realm 后端（有 realm 规则时运行）
  systemctl status gost          # GOST 后端（有 gost 规则时运行）
EOF
}

main
