#!/usr/bin/env bash
set -Eeuo pipefail

REALM_VERSION="v2.9.4"
PANEL_PORT="50002"
LISTEN_PORT="33507"
REMOTE_HOST="www.mokuoha.com"
REMOTE_PORT="33507"
PANEL_USER="admin"
PANEL_PASSWORD=""
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

If you run this script in an interactive terminal, missing values are prompted.
Press Enter to accept the shown default.

Options:
  --panel-port PORT          Internal web panel port. Default: 50002
  --listen-port PORT         Internal Realm listen port. Default: 33507
  --remote-host HOST         Forward target host. Default: www.mokuoha.com
  --remote-port PORT         Forward target port. Default: 33507
  --panel-user USER          Web panel username. Default: admin
  --panel-password PASS      Web panel password. Default: random
  --public-panel-port PORT   Optional, only used in final output.
  --public-forward-port PORT Optional, only used in final output.
  -h, --help                 Show help.

Example:
  bash install.sh --public-panel-port 50001 --public-forward-port 33507
  bash install.sh --panel-port 51006 --listen-port 21003 --remote-host 85.149.211.29 --remote-port 21003
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --panel-port) PANEL_PORT="${2:?}"; PANEL_PORT_SET=1; shift 2 ;;
    --listen-port) LISTEN_PORT="${2:?}"; LISTEN_PORT_SET=1; shift 2 ;;
    --remote-host) REMOTE_HOST="${2:?}"; REMOTE_HOST_SET=1; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:?}"; REMOTE_PORT_SET=1; shift 2 ;;
    --panel-user) PANEL_USER="${2:?}"; shift 2 ;;
    --panel-password) PANEL_PASSWORD="${2:?}"; shift 2 ;;
    --public-panel-port) PUBLIC_PANEL_PORT="${2:?}"; PUBLIC_PANEL_PORT_SET=1; shift 2 ;;
    --public-forward-port) PUBLIC_FORWARD_PORT="${2:?}"; PUBLIC_FORWARD_PORT_SET=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
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
  echo "Interactive configuration. Press Enter to use the default." > /dev/tty
  if [[ $PANEL_PORT_SET -eq 0 ]]; then
    PANEL_PORT="$(prompt_value 'Internal web panel port' "$PANEL_PORT")"
  fi
  if [[ $LISTEN_PORT_SET -eq 0 ]]; then
    LISTEN_PORT="$(prompt_value 'Internal forwarding listen port' "$LISTEN_PORT")"
  fi
  if [[ $REMOTE_HOST_SET -eq 0 ]]; then
    REMOTE_HOST="$(prompt_value 'Forward target host/IP' "$REMOTE_HOST")"
  fi
  if [[ $REMOTE_PORT_SET -eq 0 ]]; then
    REMOTE_PORT="$(prompt_value 'Forward target port' "$REMOTE_PORT")"
  fi
  if [[ $PUBLIC_PANEL_PORT_SET -eq 0 ]]; then
    PUBLIC_PANEL_PORT="$(prompt_value 'Public web panel port for output only' "${PUBLIC_PANEL_PORT:-$PANEL_PORT}")"
  fi
  if [[ $PUBLIC_FORWARD_PORT_SET -eq 0 ]]; then
    PUBLIC_FORWARD_PORT="$(prompt_value 'Public forwarding port for output only' "${PUBLIC_FORWARD_PORT:-$LISTEN_PORT}")"
  fi
}

prompt_config

[[ $EUID -eq 0 ]] || fail "Run as root."
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || fail "Invalid --panel-port"
[[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || fail "Invalid --listen-port"
[[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] || fail "Invalid --remote-port"

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
      apt-get update
      apt-get install -y curl tar python3 ca-certificates
    elif command -v yum >/dev/null 2>&1; then
      yum install -y curl tar python3 ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl tar python3 ca-certificates
    else
      fail "No supported package manager found. Install curl, tar, python3, ca-certificates manually."
    fi
  fi
}

realm_asset() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) printf 'realm-x86_64-unknown-linux-gnu.tar.gz' ;;
    aarch64|arm64) printf 'realm-aarch64-unknown-linux-gnu.tar.gz' ;;
    *) fail "Unsupported architecture: $arch" ;;
  esac
}

install_realm() {
  local asset url tmp
  asset="$(realm_asset)"
  url="https://github.com/zhboner/realm/releases/download/${REALM_VERSION}/${asset}"
  tmp="/tmp/${asset}.$$"
  mkdir -p "$REALM_DIR" "$REALM_CONFIG_DIR"
  log "Downloading Realm ${REALM_VERSION} (${asset})"
  curl -fsSL -o "$tmp" "$url"
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
  cat > "$PANEL_CONFIG_DIR/config.json" <<EOF
{
  "username": "${PANEL_USER}",
  "password": "${PANEL_PASSWORD}"
}
EOF
  chmod 0600 "$PANEL_CONFIG_DIR/config.json"
  cat > "$INSTALL_DIR/panel.py" <<'PYEOF'
#!/usr/bin/env python3
import base64, html, json, os, re, subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
CONFIG_PATH = "/etc/realm/config.toml"
PANEL_CONFIG = "/etc/realm-panel/config.json"
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = int(os.environ.get("REALM_PANEL_PORT", "50002"))
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
            current={}; continue
        if current is None or not line or line.startswith("#") or "=" not in line: continue
        key,value=line.split("=",1); key=key.strip(); value=value.strip().strip('"')
        if key in ("listen","remote"): current[key]=value
    if current: endpoints.append(current)
    return [e for e in endpoints if "listen" in e and "remote" in e]
def write_endpoints(endpoints):
    tmp=CONFIG_PATH+".tmp"
    with open(tmp,"w",encoding="utf-8") as f:
        f.write(BASE_CONFIG)
        for e in endpoints:
            f.write("\n[[endpoints]]\n"); f.write(f'listen = "{e["listen"]}"\n'); f.write(f'remote = "{e["remote"]}"\n')
    os.replace(tmp, CONFIG_PATH)
def validate_port(value):
    port=int(value)
    if port < 1 or port > 65535: raise ValueError("port must be between 1 and 65535")
    return port
def validate_remote(host, port):
    if not HOST_RE.match(host): raise ValueError("invalid target address")
    return f"{host}:{validate_port(port)}"
def apply_realm_state(endpoints):
    if endpoints:
        run(["systemctl","enable","realm"]); run(["systemctl","restart","realm"])
    else:
        run(["systemctl","stop","realm"])
class Handler(BaseHTTPRequestHandler):
    server_version="RealmPanel/1.0"
    def log_message(self, fmt, *args): return
    def authorized(self):
        cfg=json.load(open(PANEL_CONFIG, encoding="utf-8")); expected="Basic "+base64.b64encode(f'{cfg["username"]}:{cfg["password"]}'.encode()).decode()
        return self.headers.get("Authorization","") == expected
    def require_auth(self): self.send_response(401); self.send_header("WWW-Authenticate", 'Basic realm="Realm Panel"'); self.end_headers()
    def send_html(self, body, status=200):
        data=body.encode("utf-8"); self.send_response(status); self.send_header("Content-Type","text/html; charset=utf-8"); self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
    def redirect(self): self.send_response(303); self.send_header("Location","/"); self.end_headers()
    def do_GET(self):
        if not self.authorized(): return self.require_auth()
        if self.path.startswith("/logs"):
            _,out=run(["journalctl","-u","realm","-n","120","--no-pager"]); return self.page(pre="$ journalctl -u realm -n 120 --no-pager\n"+out)
        _,active=run(["systemctl","is-active","realm"]); _,enabled=run(["systemctl","is-enabled","realm"])
        rows=[]
        for idx,e in enumerate(parse_endpoints()):
            rows.append(f"""<tr><td>{idx+1}</td><td>{html.escape(e['listen'])}</td><td>{html.escape(e['remote'])}</td><td><form method="post" action="/delete" onsubmit="return confirm('Delete this rule?')"><input type="hidden" name="idx" value="{idx}"><button class="danger">Delete</button></form></td></tr>""")
        body=f"""<div class="top"><div><h1>Realm Forward Panel</h1><p>realm: <b>{html.escape(active)}</b> / {html.escape(enabled)}</p></div><div><a href="/logs">Logs</a></div></div><section><h2>Add Forward</h2><form method="post" action="/add" class="grid"><label>Listen Port<input name="listen_port" placeholder="33507" required pattern="[0-9]+"></label><label>Target Host<input name="remote_host" placeholder="www.mokuoha.com" required></label><label>Target Port<input name="remote_port" placeholder="33507" required pattern="[0-9]+"></label><button>Add and Restart</button></form></section><section><h2>Current Rules</h2><table><thead><tr><th>#</th><th>Listen</th><th>Target</th><th>Action</th></tr></thead><tbody>{''.join(rows) or '<tr><td colspan="4">No rules</td></tr>'}</tbody></table></section><section><form method="post" action="/restart"><button>Restart Realm</button></form></section>"""
        self.page(body=body)
    def do_POST(self):
        if not self.authorized(): return self.require_auth()
        form=parse_qs(self.rfile.read(int(self.headers.get("Content-Length","0"))).decode("utf-8"))
        try:
            if self.path == "/add":
                listen_port=validate_port(form.get("listen_port",[""])[0]); remote=validate_remote(form.get("remote_host",[""])[0].strip(), form.get("remote_port",[""])[0]); endpoints=parse_endpoints(); listen=f"0.0.0.0:{listen_port}"
                if any(e["listen"] == listen for e in endpoints): raise ValueError("listen port already exists")
                endpoints.append({"listen":listen,"remote":remote}); write_endpoints(endpoints); apply_realm_state(endpoints)
            elif self.path == "/delete":
                idx=int(form.get("idx",["-1"])[0]); endpoints=parse_endpoints()
                if idx < 0 or idx >= len(endpoints): raise ValueError("rule not found")
                del endpoints[idx]; write_endpoints(endpoints); apply_realm_state(endpoints)
            elif self.path == "/restart": apply_realm_state(parse_endpoints())
            else: raise ValueError("unknown action")
            self.redirect()
        except Exception as exc: self.page(body=f'<p class="error">{html.escape(str(exc))}</p><p><a href="/">Back</a></p>', status=400)
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

Install complete.

Panel:
  URL: http://${ip}:${PUBLIC_PANEL_PORT:-$PANEL_PORT}
  Username: ${PANEL_USER}
  Password: ${PANEL_PASSWORD}

Forward:
  Public: ${ip}:${PUBLIC_FORWARD_PORT:-$LISTEN_PORT}
  Internal listen: 0.0.0.0:${LISTEN_PORT}
  Remote: ${REMOTE_HOST}:${REMOTE_PORT}

Services:
  systemctl status realm
  systemctl status realm-panel
EOF
}

main
