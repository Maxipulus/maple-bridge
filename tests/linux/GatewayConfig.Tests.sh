#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
renderer="$repository_root/scripts/linux/render-gateway-config.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

private_key='AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA='
client_public_key='ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A='
replacement_public_key='QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVpbXF1eX2A='
printf '%s\n' "$private_key" > "$test_root/server.key"
chmod 0600 "$test_root/server.key"

output_dir="$test_root/output"
bash "$renderer" \
    --output-dir "$output_dir" \
    --server-private-key-file "$test_root/server.key" \
    --client-public-key "$client_public_key" \
    --external-interface eth0 \
    --vpn-port 51820 \
    --server-address 10.88.0.1/24 \
    --client-address 10.88.0.2/32

grep -Fq 'PrivateKey = AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=' "$output_dir/wg-maplebridge.conf"
grep -Fq 'PublicKey = ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=' "$output_dir/wg-maplebridge.conf"
grep -Fq 'AllowedIPs = 10.88.0.2/32' "$output_dir/wg-maplebridge.conf"
grep -Fq 'udp dport $vpn_port accept' "$output_dir/maplebridge.nft"
grep -Fq 'iifname $wg_if oifname $wan_if accept' "$output_dir/maplebridge.nft"
grep -Fq 'ip saddr $vpn_net oifname $wan_if masquerade' "$output_dir/maplebridge.nft"
grep -Fq 'net.ipv4.ip_forward = 1' "$output_dir/99-maplebridge-forward.conf"
grep -Fq 'Before=network.target wg-quick@wg-maplebridge.service' "$output_dir/maplebridge-firewall.service"

[[ "$(stat -c '%a' "$output_dir/wg-maplebridge.conf")" == '600' ]]
[[ "$(stat -c '%a' "$output_dir/maplebridge.nft")" == '600' ]]
[[ "$(stat -c '%a' "$output_dir/99-maplebridge-forward.conf")" == '644' ]]

if [[ "${MAPLEBRIDGE_NFT_CHECK:-0}" == '1' ]]; then
    nft -c -f "$output_dir/maplebridge.nft"
fi

first_hashes="$(sha256sum "$output_dir"/*)"
bash "$renderer" \
    --output-dir "$output_dir" \
    --server-private-key-file "$test_root/server.key" \
    --client-public-key "$client_public_key" \
    --external-interface eth0
second_hashes="$(sha256sum "$output_dir"/*)"
[[ "$first_hashes" == "$second_hashes" ]]
[[ "$(cat "$test_root/server.key")" == "$private_key" ]]

invalid_output="$test_root/invalid"
if bash "$renderer" \
    --output-dir "$invalid_output" \
    --server-private-key-file "$test_root/server.key" \
    --client-public-key "$replacement_public_key" \
    --external-interface 'eth0;bad' 2>/dev/null; then
    printf 'Expected an invalid interface to be rejected.\n' >&2
    exit 1
fi
[[ ! -e "$invalid_output/wg-maplebridge.conf" ]]

printf 'Gateway config tests passed.\n'
