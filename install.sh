#!/usr/bin/env bash
set -Eeuo pipefail

REALM_VERSION="v2.9.4"
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

if [[ -z "$PANEL_PASSWORD" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    PANEL_PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 18)"
  else
    PANEL_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18)"
  fi
fi

install_packages() {
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update || warn "apt-get update 失败，可能是某个软件源失效；继续尝试安装依赖。"
      apt-get install -y curl tar python3 ca-certificates
    elif command -v yum >/dev/null 2>&1; then
      yum install -y curl tar python3 ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl tar python3 ca-certificates
    else
      fail "未找到支持的包管理器，请手动安装 curl、tar、python3、ca-certificates。"
    fi
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

write_realm_config() {
  cat > "$REALM_CONFIG_DIR/config.toml" <<EOF
[log]
level = "info"
output = "stdout"

[network]
use_udp = true
tcp_timeout = 10
udp_timeout = 30
tcp_keepalive = 60

[[endpoints]]
listen = "0.0.0.0:${LISTEN_PORT}"
remote = "${REMOTE_HOST}:${REMOTE_PORT}"
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
import base64, hashlib, hmac, html, json, os, re, subprocess, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
CONFIG_PATH = "/etc/realm/config.toml"
PANEL_CONFIG = "/etc/realm-panel/config.json"
LISTEN_HOST = os.environ.get("REALM_PANEL_BIND", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("REALM_PANEL_PORT", "50002"))
FAILED_ATTEMPTS = {}
FAILED_LOCK = threading.Lock()
MAX_ATTEMPTS = 10
WINDOW_SECONDS = 300
HOST_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,253}$")
BASE_CONFIG = """[log]
level = \"info\"
output = \"stdout\"

[network]
use_udp = true
tcp_timeout = 10
udp_timeout = 30
tcp_keepalive = 60
""".strip() + "\n"
def run(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30)
    return proc.returncode, proc.stdout.strip()
def parse_endpoints():
    if not os.path.exists(CONFIG_PATH): return []
    lines = open(CONFIG_PATH, encoding="utf-8").readlines(); endpoints=[]; current=None
    for raw in lines:
        line=raw.strip()
        if line == "[[endpoints]]":
            if current: endpoints.append(current)
            current={"udp": True, "note": ""}; continue
        if current is not None and line.startswith("# note-b64 ="):
            try: current["note"]=base64.b64decode(line.split("=",1)[1].strip()).decode("utf-8")
            except Exception: current["note"]=""
            continue
        if current is None or not line or line.startswith("#") or "=" not in line: continue
        key,value=line.split("=",1); key=key.strip(); raw_value=value.strip()
        if key in ("listen","remote"): current[key]=raw_value.strip('"')
        elif key == "network": current["udp"] = "use_udp = false" not in raw_value.lower()
    if current: endpoints.append(current)
    return [e for e in endpoints if "listen" in e and "remote" in e]
def write_endpoints(endpoints):
    tmp=CONFIG_PATH+".tmp"
    with open(tmp,"w",encoding="utf-8") as f:
        f.write(BASE_CONFIG)
        for e in endpoints:
            f.write("\n[[endpoints]]\n")
            if e.get("note"): f.write(f'# note-b64 = {base64.b64encode(e["note"].encode()).decode()}\n')
            f.write(f'listen = "{e["listen"]}"\n'); f.write(f'remote = "{e["remote"]}"\n')
            f.write("network = { use_udp = %s }\n" % ("true" if e.get("udp", True) else "false"))
    os.replace(tmp, CONFIG_PATH)
def validate_port(value):
    port=int(value)
    if port < 1 or port > 65535: raise ValueError("端口必须在 1 到 65535 之间")
    return port
def validate_remote(host, port):
    if not HOST_RE.match(host): raise ValueError("目标地址不合法")
    return f"{host}:{validate_port(port)}"
def validate_note(value):
    value=value.strip()
    if len(value) > 40: raise ValueError("备注不能超过 40 个字符")
    if any(ord(c) < 32 for c in value): raise ValueError("备注含非法字符")
    return value
def apply_realm_state(endpoints):
    if endpoints:
        run(["systemctl","enable","realm"]); run(["systemctl","restart","realm"])
    else:
        run(["systemctl","stop","realm"])
def verify_credentials(username, password):
    cfg=json.load(open(PANEL_CONFIG, encoding="utf-8"))
    if not hmac.compare_digest(username, cfg["username"]): return False
    salt=bytes.fromhex(cfg["salt"]); expected=bytes.fromhex(cfg["hash"])
    digest=hashlib.pbkdf2_hmac("sha256", password.encode(), salt, cfg["iterations"])
    return hmac.compare_digest(digest, expected)
def rate_limited(key):
    now=time.time()
    with FAILED_LOCK:
        hits=[t for t in FAILED_ATTEMPTS.get(key, []) if now-t < WINDOW_SECONDS]
        FAILED_ATTEMPTS[key]=hits
        return len(hits) >= MAX_ATTEMPTS
def record_failure(key):
    with FAILED_LOCK:
        FAILED_ATTEMPTS.setdefault(key, []).append(time.time())
class Handler(BaseHTTPRequestHandler):
    server_version="RealmPanel/1.0"
    def log_message(self, fmt, *args): return
    def authorized(self):
        client=self.client_address[0]
        if rate_limited(client): return False
        header=self.headers.get("Authorization","")
        if not header.startswith("Basic "):
            return False
        try:
            username,_,password=base64.b64decode(header[6:]).decode("utf-8").partition(":")
        except Exception:
            record_failure(client); return False
        if verify_credentials(username, password): return True
        record_failure(client); return False
    def require_auth(self): self.send_response(401); self.send_header("WWW-Authenticate", 'Basic realm="Realm Panel"'); self.end_headers()
    def send_html(self, body, status=200):
        data=body.encode("utf-8"); self.send_response(status); self.send_header("Content-Type","text/html; charset=utf-8"); self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
    def redirect(self): self.send_response(303); self.send_header("Location","/"); self.end_headers()
    def do_GET(self):
        if not self.authorized(): return self.require_auth()
        if self.path.startswith("/logs"):
            _,out=run(["journalctl","-u","realm","-n","120","--no-pager"]); return self.page(pre="$ journalctl -u realm -n 120 --no-pager\n"+out)
        _,active=run(["systemctl","is-active","realm"]); _,enabled=run(["systemctl","is-enabled","realm"])
        status_class="ok" if active=="active" else "bad"
        rows=[]
        for idx,e in enumerate(parse_endpoints()):
            udp_badge='<span class="badge on">UDP 开</span>' if e.get("udp", True) else '<span class="badge off">UDP 关</span>'
            note=html.escape(e.get("note","")) or '<span class="muted">—</span>'
            rows.append(f"""<tr><td>{idx+1}</td><td>{html.escape(e['listen'])}</td><td>{html.escape(e['remote'])}</td><td>{udp_badge}</td><td>{note}</td><td class="actions"><form method="post" action="/edit#edit"><input type="hidden" name="idx" value="{idx}"><button class="ghost">编辑</button></form><form method="post" action="/delete" onsubmit="return confirm('确认删除这条转发规则？')"><input type="hidden" name="idx" value="{idx}"><button class="danger">删除</button></form></td></tr>""")
        table='<tr><td colspan="6" class="muted">暂无转发规则</td></tr>' if not rows else ''.join(rows)
        body=f"""<div class="top"><div><h1>Realm 转发面板</h1><p>realm 服务：<b class="{status_class}">{html.escape(active)}</b> / 开机自启：{html.escape(enabled)}</p></div><div><a href="/logs">查看日志</a></div></div><section id="add"><h2>新增转发</h2><form method="post" action="/add" class="grid"><label>本地监听端口<input name="listen_port" placeholder="33507" required pattern="[0-9]+" inputmode="numeric"></label><label>目标地址<input name="remote_host" placeholder="www.mokuoha.com" required></label><label>目标端口<input name="remote_port" placeholder="33507" required pattern="[0-9]+" inputmode="numeric"></label><label>备注（可选）<input name="note" maxlength="40" placeholder="用途说明"></label><label class="check"><input type="checkbox" name="udp" value="1" checked>转发 UDP</label><button>新增并重启</button></form></section><section><h2>当前规则</h2><div class="tablewrap"><table><thead><tr><th>#</th><th>本地监听</th><th>转发目标</th><th>UDP</th><th>备注</th><th>操作</th></tr></thead><tbody>{table}</tbody></table></div></section><section><form method="post" action="/restart"><button>重启 Realm</button></form></section>"""
        self.page(body=body)
    def edit_page(self, idx):
        endpoints=parse_endpoints()
        if idx < 0 or idx >= len(endpoints): raise ValueError("规则不存在")
        e=endpoints[idx]
        listen_port=e["listen"].rsplit(":",1)[-1]
        remote_host,_,remote_port=e["remote"].rpartition(":")
        checked="checked" if e.get("udp", True) else ""
        body=f"""<div class="top"><div><h1>编辑转发规则</h1></div><div><a href="/">返回</a></div></div><section><form method="post" action="/update" class="grid"><input type="hidden" name="idx" value="{idx}"><label>本地监听端口<input name="listen_port" value="{html.escape(listen_port)}" required pattern="[0-9]+" inputmode="numeric"></label><label>目标地址<input name="remote_host" value="{html.escape(remote_host)}" required></label><label>目标端口<input name="remote_port" value="{html.escape(remote_port)}" required pattern="[0-9]+" inputmode="numeric"></label><label>备注（可选）<input name="note" maxlength="40" value="{html.escape(e.get('note',''))}"></label><label class="check"><input type="checkbox" name="udp" value="1" {checked}>转发 UDP</label><button>保存并重启</button></form></section>"""
        self.page(body=body)
    def do_POST(self):
        if not self.authorized(): return self.require_auth()
        form=parse_qs(self.rfile.read(int(self.headers.get("Content-Length","0"))).decode("utf-8"))
        try:
            if self.path == "/edit":
                return self.edit_page(int(form.get("idx",["-1"])[0]))
            if self.path == "/add":
                listen_port=validate_port(form.get("listen_port",[""])[0]); remote=validate_remote(form.get("remote_host",[""])[0].strip(), form.get("remote_port",[""])[0]); note=validate_note(form.get("note",[""])[0]); udp="1" in form.get("udp",[]); endpoints=parse_endpoints(); listen=f"0.0.0.0:{listen_port}"
                if any(e["listen"] == listen for e in endpoints): raise ValueError("该监听端口已存在")
                endpoints.append({"listen":listen,"remote":remote,"udp":udp,"note":note}); write_endpoints(endpoints); apply_realm_state(endpoints)
            elif self.path == "/update":
                idx=int(form.get("idx",["-1"])[0]); endpoints=parse_endpoints()
                if idx < 0 or idx >= len(endpoints): raise ValueError("规则不存在")
                listen_port=validate_port(form.get("listen_port",[""])[0]); remote=validate_remote(form.get("remote_host",[""])[0].strip(), form.get("remote_port",[""])[0]); note=validate_note(form.get("note",[""])[0]); udp="1" in form.get("udp",[]); listen=f"0.0.0.0:{listen_port}"
                if any(i != idx and e["listen"] == listen for i,e in enumerate(endpoints)): raise ValueError("该监听端口已存在")
                endpoints[idx]={"listen":listen,"remote":remote,"udp":udp,"note":note}; write_endpoints(endpoints); apply_realm_state(endpoints)
            elif self.path == "/delete":
                idx=int(form.get("idx",["-1"])[0]); endpoints=parse_endpoints()
                if idx < 0 or idx >= len(endpoints): raise ValueError("规则不存在")
                del endpoints[idx]; write_endpoints(endpoints); apply_realm_state(endpoints)
            elif self.path == "/restart": apply_realm_state(parse_endpoints())
            else: raise ValueError("未知操作")
            self.redirect()
        except Exception as exc: self.page(body=f'<p class="error">{html.escape(str(exc))}</p><p><a href="/">返回</a></p>', status=400)
    def page(self, body="", pre="", status=200):
        pre_html=f"<pre>{html.escape(pre)}</pre>" if pre else ""
        self.send_html(f"""<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Realm Panel</title><style>body{{font-family:system-ui,-apple-system,Segoe UI,sans-serif;margin:0;background:#f6f7f9;color:#14181f}}main{{max-width:980px;margin:32px auto;padding:0 18px}}section,.top{{background:#fff;border:1px solid #e3e7ee;border-radius:8px;padding:20px;margin:16px 0}}.top{{display:flex;justify-content:space-between;align-items:center}}h1{{margin:0;font-size:26px}}h2{{margin-top:0;font-size:18px}}table{{width:100%;border-collapse:collapse}}th,td{{padding:12px;border-bottom:1px solid #edf0f5;text-align:left}}input{{display:block;margin-top:6px;padding:10px;border:1px solid #cbd3df;border-radius:6px;min-width:180px}}button{{padding:10px 14px;border:0;border-radius:6px;background:#155eef;color:white;font-weight:600;cursor:pointer}}button.danger{{background:#d92d20}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:14px;align-items:end}}pre{{white-space:pre-wrap;background:#101828;color:#e6edf7;padding:16px;border-radius:8px;overflow:auto}}.error{{color:#b42318;font-weight:700}}a{{color:#155eef;text-decoration:none}}</style></head><body><main>{body}{pre_html}</main></body></html>""", status)
if __name__ == "__main__": ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
PYEOF
  chmod 0755 "$INSTALL_DIR/panel.py"
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
  write_realm_config
  write_realm_service
  write_panel
  write_panel_service
  systemctl daemon-reload
  systemctl enable realm realm-panel
  systemctl restart realm
  systemctl restart realm-panel
  sleep 1
  systemctl is-active --quiet realm || fail "realm failed to start"
  systemctl is-active --quiet realm-panel || fail "realm-panel failed to start"
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

转发:
  公网入口: ${ip}:${PUBLIC_FORWARD_PORT:-$LISTEN_PORT}
  内部监听: 0.0.0.0:${LISTEN_PORT}
  目标: ${REMOTE_HOST}:${REMOTE_PORT}

服务:
  systemctl status realm
  systemctl status realm-panel
EOF
}

main
