#!/bin/bash

#######################################
# VPN 헬스체크 스크립트
# 매분 실행하여 updated_at만 업데이트 (살아있음 표시)
#######################################

DB_HOST="220.121.120.83"
DB_USER="vpnuser"
DB_PASS="vpn1324"
DB_NAME="vpn"
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

# 로컬 WireGuard 인터페이스 확인 및 updated_at 업데이트
FOUND=0
for wg_iface in $(ls /etc/wireguard/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//'); do
    log "인터페이스 체크: $wg_iface"

    # WireGuard 인터페이스가 실제로 떠있는지 확인
    if wg show "$wg_iface" > /dev/null 2>&1; then
        # 포트 확인
        PORT=$(grep "^ListenPort" /etc/wireguard/${wg_iface}.conf | awk '{print $3}' | tr -d ' ')

        if [ -n "$PORT" ]; then
            log "  → 포트: $PORT"

            # DB에 updated_at만 업데이트 (살아있음 표시)
            ERROR=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
                "UPDATE vpn_servers SET updated_at = CURRENT_TIMESTAMP WHERE public_ip = '$MY_IP' AND port = $PORT" 2>&1)

            if [ $? -eq 0 ]; then
                log "  ✅ DB 업데이트 성공: $MY_IP:$PORT"
                FOUND=1
            else
                log "  ❌ DB 업데이트 실패: $ERROR"
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
