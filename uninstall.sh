#!/usr/bin/env bash
set -Eeuo pipefail

INSTALL_DIR="/opt/realm-panel"
PANEL_CONFIG_DIR="/etc/realm-panel"
REALM_DIR="/opt/realm"
REALM_CONFIG_DIR="/etc/realm"
PURGE=0

usage() {
  cat <<'EOF'
Usage:
  bash uninstall.sh [--purge]

停止并移除 realm 与 realm-panel 服务及其程序文件。

参数:
  --purge      同时删除配置目录（/etc/realm、/etc/realm-panel）。
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

for svc in realm-panel realm; do
  if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
  fi
  rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload

rm -rf "$INSTALL_DIR" "$REALM_DIR"
log "已移除程序文件与服务。"

if [[ $PURGE -eq 1 ]]; then
  rm -rf "$PANEL_CONFIG_DIR" "$REALM_CONFIG_DIR"
  log "已删除配置目录。"
else
  log "配置目录已保留：$REALM_CONFIG_DIR、$PANEL_CONFIG_DIR（用 --purge 一并删除）。"
fi

log "卸载完成。"
