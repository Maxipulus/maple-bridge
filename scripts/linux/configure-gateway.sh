#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    printf 'Error: configure-gateway.sh must run as root.\n' >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
client_public_key=''
vpn_port='51820'
server_address='10.88.0.1/24'
client_address='10.88.0.2/32'
external_interface=''

while [[ $# -gt 0 ]]; do
    case "$1" in
        --client-public-key) client_public_key="${2-}"; shift 2 ;;
        --vpn-port) vpn_port="${2-}"; shift 2 ;;
        --server-address) server_address="${2-}"; shift 2 ;;
        --client-address) client_address="${2-}"; shift 2 ;;
        --external-interface) external_interface="${2-}"; shift 2 ;;
        *) printf 'Error: unknown argument: %s\n' "$1" >&2; exit 1 ;;
    esac
done

if [[ -z "$client_public_key" ]]; then
    printf 'Error: --client-public-key is required.\n' >&2
    exit 1
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
fi
if [[ "${ID:-}" != 'ubuntu' ]]; then
    printf 'Error: this initial gateway script supports Ubuntu only.\n' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends wireguard-tools nftables

if [[ -z "$external_interface" ]]; then
    external_interface="$(ip -4 route show default | awk 'NR == 1 { print $5 }')"
fi
if [[ -z "$external_interface" ]]; then
    printf 'Error: unable to detect the default IPv4 interface.\n' >&2
    exit 1
fi

install -d -m 0700 /etc/maplebridge/keys
server_private_key_file='/etc/maplebridge/keys/server.key'
if [[ ! -f "$server_private_key_file" ]]; then
    umask 077
    temporary_key="$(mktemp /etc/maplebridge/keys/server.key.XXXXXXXX)"
    trap 'rm -f -- "${temporary_key:-}"' EXIT
    wg genkey > "$temporary_key"
    chmod 0600 "$temporary_key"
    mv -- "$temporary_key" "$server_private_key_file"
    temporary_key=''
fi

render_dir="$(mktemp -d)"
trap 'rm -rf -- "${render_dir:-}"; rm -f -- "${temporary_key:-}"' EXIT
bash "$script_dir/render-gateway-config.sh" \
    --output-dir "$render_dir" \
    --server-private-key-file "$server_private_key_file" \
    --client-public-key "$client_public_key" \
    --external-interface "$external_interface" \
    --vpn-port "$vpn_port" \
    --server-address "$server_address" \
    --client-address "$client_address"

install -d -m 0755 /etc/wireguard /etc/maplebridge
install -m 0600 "$render_dir/wg-maplebridge.conf" /etc/wireguard/wg-maplebridge.conf
install -m 0600 "$render_dir/maplebridge.nft" /etc/maplebridge/maplebridge.nft
install -m 0644 "$render_dir/99-maplebridge-forward.conf" /etc/sysctl.d/99-maplebridge-forward.conf
install -m 0644 "$render_dir/maplebridge-firewall.service" /etc/systemd/system/maplebridge-firewall.service

sysctl --system >/dev/null
systemctl daemon-reload
systemctl enable maplebridge-firewall.service wg-quick@wg-maplebridge.service
systemctl restart maplebridge-firewall.service
systemctl restart wg-quick@wg-maplebridge.service

server_public_key="$(wg pubkey < "$server_private_key_file")"
printf 'MapleBridge gateway configured.\n'
printf 'Server public key: %s\n' "$server_public_key"
printf 'WireGuard interface: wg-maplebridge\n'
printf 'WireGuard UDP port: %s\n' "$vpn_port"
