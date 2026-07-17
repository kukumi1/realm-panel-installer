#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/realm-panel"
PANEL_CONFIG_DIR="/etc/realm-panel"
REALM_DIR="/opt/realm"
REALM_CONFIG_DIR="/etc/realm"
GOST_DIR="/opt/gost"
GOST_CONFIG_DIR="/etc/gost"
UNIT_DIR="/etc/systemd/system"
PURGE=0

usage() {
  cat <<'EOF'
Usage:
  bash uninstall.sh [--purge]

停止并移除 realm、gost、realm-panel 服务、socat 动态单元及其程序文件。

参数:
  --purge      同时删除配置目录（/etc/realm、/etc/gost、/etc/realm-panel）。
               默认保留配置，方便重装后沿用。
  -h, --help   显示帮助。
EOF
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "未知参数: $1" ;;
  esac
done

[[ $EUID -eq 0 ]] || fail "请使用 root 用户运行。"

for unit in "$UNIT_DIR"/rp-socat-*.service; do
  [[ -e "$unit" ]] || continue
  name="$(basename "$unit")"
  systemctl disable --now "$name" 2>/dev/null || true
  rm -f "$unit"
done

systemctl disable --now realm-panel-ddns.timer 2>/dev/null || true
systemctl stop realm-panel-ddns.service 2>/dev/null || true
rm -f "$UNIT_DIR/realm-panel-ddns.timer" "$UNIT_DIR/realm-panel-ddns.service"

for svc in realm-panel realm gost; do
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
  rm -f "$UNIT_DIR/${svc}.service"
done
systemctl daemon-reload

if command -v nft >/dev/null 2>&1; then
  nft delete table ip realmpanel 2>/dev/null || true
fi
if command -v iptables >/dev/null 2>&1; then
  for chain in DOCKER-USER FORWARD; do
    while iptables -C "$chain" -j REALM_PANEL_FWD 2>/dev/null; do
      iptables -D "$chain" -j REALM_PANEL_FWD 2>/dev/null || break
    done
  done
  iptables -F REALM_PANEL_FWD 2>/dev/null || true
  iptables -X REALM_PANEL_FWD 2>/dev/null || true
fi
log "已清理 nftables 转发表与 FORWARD 放行链。"

rm -rf "$INSTALL_DIR" "$REALM_DIR" "$GOST_DIR"
log "已移除程序文件与服务。"

rm -f /etc/sysctl.d/99-realm-panel-forward.conf

if [[ $PURGE -eq 1 ]]; then
  rm -rf "$PANEL_CONFIG_DIR" "$REALM_CONFIG_DIR" "$GOST_CONFIG_DIR"
  log "已删除配置目录。"
else
  log "配置目录已保留：$REALM_CONFIG_DIR、$GOST_CONFIG_DIR、$PANEL_CONFIG_DIR（用 --purge 一并删除）。"
fi

log "卸载完成。"
