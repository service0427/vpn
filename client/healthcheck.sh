#!/bin/bash

#######################################
# VPN 헬스체크 스크립트
# 매분 실행하여 updated_at만 업데이트 (살아있음 표시)
#######################################

API_HOST="112.161.221.82"
LOG_FILE="/var/log/vpn-healthcheck.log"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "===== 헬스체크 시작 ====="

# 현재 서버의 공인 IP 확인
log "공인 IP 확인 중..."
MY_IP=$(curl -s -m 5 ifconfig.me 2>/dev/null || curl -s -m 5 api.ipify.org 2>/dev/null)

if [ -z "$MY_IP" ]; then
    log "❌ 공인 IP 확인 실패"
    exit 1
fi
log "✅ 공인 IP: $MY_IP"

# 로컬 WireGuard 인터페이스 확인 및 heartbeat 전송
FOUND=0
for wg_iface in $(ls /etc/wireguard/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//'); do
    log "인터페이스 체크: $wg_iface"

    # WireGuard 인터페이스가 실제로 떠있는지 확인
    if wg show "$wg_iface" > /dev/null 2>&1; then
        # 포트 확인
        PORT=$(grep "^ListenPort" /etc/wireguard/${wg_iface}.conf | awk '{print $3}' | tr -d ' ')

        if [ -n "$PORT" ]; then
            log "  → 포트: $PORT"

            # API를 통해 heartbeat 전송
            RESPONSE=$(curl -s -m 5 -X POST http://$API_HOST/api/vpn/heartbeat \
                -H "Content-Type: application/json" \
                -d "{\"public_ip\":\"$MY_IP\",\"port\":$PORT}" 2>&1)

            if echo "$RESPONSE" | grep -q '"success":true'; then
                log "  ✅ Heartbeat 성공: $MY_IP:$PORT"
                FOUND=1
            else
                log "  ❌ Heartbeat 실패: $RESPONSE"
            fi
        else
            log "  ⚠️  포트 정보 없음"
        fi
    else
        log "  ⚠️  인터페이스 비활성"
    fi
done

if [ $FOUND -eq 0 ]; then
    log "❌ 업데이트된 인터페이스 없음"
else
    log "✅ 헬스체크 완료"
fi
