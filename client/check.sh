#!/bin/bash

#######################################
# VPN 상태 확인 스크립트
#######################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📡 VPN 상태 확인"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# WireGuard 인터페이스 확인
echo "🔍 로컬 WireGuard 인터페이스:"
if ls /etc/wireguard/wg*.conf >/dev/null 2>&1; then
    for conf in /etc/wireguard/wg*.conf; do
        iface=$(basename "$conf" .conf)
        if wg show "$iface" >/dev/null 2>&1; then
            port=$(grep "^ListenPort" "$conf" | awk '{print $3}' | tr -d ' ')
            peer_count=$(wg show "$iface" | grep -c "^peer:")
            echo "  ✅ $iface (포트: $port, 피어: $peer_count)"
        fi
    done
else
    echo "  ❌ WireGuard 설정 없음"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔗 API에서 가져온 활성 VPN 목록:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

API_HOST="220.121.120.83"
VPN_LIST=$(curl -s http://$API_HOST/vpn_socks5/api/servers.php?active=true)

if [ $? -eq 0 ] && [ -n "$VPN_LIST" ]; then
    echo "$VPN_LIST" | jq -r '.vpns[] | "\(.public_ip):\(.port)"' | nl -w2 -s". "

    TOTAL=$(echo "$VPN_LIST" | jq -r '.vpns | length')
    echo ""
    echo "총 $TOTAL개의 활성 VPN 서버"
else
    echo "❌ API 연결 실패"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
