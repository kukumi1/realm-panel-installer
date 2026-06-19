# Realm Forward Panel Installer

One-command installer for a NAT VPS forwarding node. It installs:

- Realm forwarding core
- A simple Basic Auth web panel
- systemd services for both
- One default forwarding rule

## Interactive use

Run this on the NAT VPS as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Promiscuity1/realm-panel-installer/main/install.sh)
```

It will ask for:

- internal web panel port
- internal forwarding listen port
- target host/IP
- target port
- public panel port for final output
- public forwarding port for final output

Press Enter to accept each default.

## One-line default use

If your NAT panel maps:

- external `50001` -> internal `50002` for the web panel
- external `33507` -> internal `33507` for forwarding

Run on the VPS as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Promiscuity1/realm-panel-installer/main/install.sh) --public-panel-port 50001 --public-forward-port 33507
```

Default rule:

```text
0.0.0.0:33507 -> www.mokuoha.com:33507
```

## Custom target

```bash
bash install.sh \
  --panel-port 50002 \
  --listen-port 33507 \
  --remote-host www.mokuoha.com \
  --remote-port 33507 \
  --public-panel-port 50001 \
  --public-forward-port 33507
```

## Manage services

```bash
systemctl status realm
systemctl status realm-panel
journalctl -u realm -f
journalctl -u realm-panel -f
```
