#!/usr/bin/env bash
# Read-only VPN connection state. It never reveals connection names or peers.

VPN_STATE='unknown'
VPN_ACTIVE_COUNT=0
VPN_CONNECTION_DURATION='not connected'

collect_vpn_state() {
  local output line connection_type timestamp now oldest_timestamp=0
  VPN_STATE='unknown'
  VPN_ACTIVE_COUNT=0
  VPN_CONNECTION_DURATION='not connected'
  if ! output="$(LC_ALL=C nmcli --terse --fields TYPE,TIMESTAMP connection show --active 2>/dev/null)"; then
    VPN_CONNECTION_DURATION='unknown (query failed)'
    return 1
  fi
  while IFS= read -r line; do
    IFS=':' read -r connection_type timestamp <<< "${line}"
    case "${connection_type}" in
      vpn|wireguard|tun|ppp)
        ((VPN_ACTIVE_COUNT += 1))
        if [[ "${timestamp}" =~ ^[0-9]+$ ]] && { (( oldest_timestamp == 0 )) || (( timestamp < oldest_timestamp )); }; then
          oldest_timestamp="${timestamp}"
        fi
        ;;
    esac
  done <<< "${output}"
  if (( VPN_ACTIVE_COUNT == 0 )); then
    VPN_STATE='inactive'
    return 0
  fi
  VPN_STATE='active'
  if (( oldest_timestamp == 0 )); then
    VPN_CONNECTION_DURATION='unknown (timestamp unavailable)'
    return 0
  fi
  now="$(date -u +%s)"
  if (( now < oldest_timestamp )); then
    VPN_CONNECTION_DURATION='unknown (timestamp invalid)'
  else
    VPN_CONNECTION_DURATION="$(format_elapsed_seconds "$(( now - oldest_timestamp ))")"
  fi
}
