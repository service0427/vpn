#!/bin/bash

#######################################
# macvlan 헬스체크 및 VPN 서버 자동 업데이트
# - macvlan IP 변경 감지
# - VPN 서버 설정 자동 업데이트
# - API 자동 재등록
#######################################

API_HOST="112.161.221.82"
BASE_PORT=55555
STATE_FILE="/var/lib/vpn/macvlan-state.txt"

mkdir -p /var/lib/vpn

# 현재 상태 파일 로드
declare -A PREV_IPS
if [ -f "$STATE_FILE" ]; then
    while IFS='=' read -r iface ip; do
        PREV_IPS[$iface]="$ip"
    done < "$STATE_FILE"
fi

# macvlan IP 확인 및 변경 감지
CHANGED=0
> "$STATE_FILE.new"

for i in 0 1 2 3; do
    IFACE="macvlan$i"
    CURRENT_IP=$(ip -4 addr show $IFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)

    # 연결 상태 확인
    if [ -z "$CURRENT_IP" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $IFACE - IP 없음, 재연결 시도" | tee -a /var/log/macvlan-healthcheck.log
        nmcli connection up $IFACE &>/dev/null
        sleep 5
        CURRENT_IP=$(ip -4 addr show $IFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    fi

    # IP 있는 경우에만 처리
    if [ -n "$CURRENT_IP" ]; then
        echo "$IFACE=$CURRENT_IP" >> "$STATE_FILE.new"

        # IP 변경 감지
        PREV_IP="${PREV_IPS[$IFACE]}"
        if [ "$PREV_IP" != "$CURRENT_IP" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $IFACE - IP 변경 감지 ($PREV_IP -> $CURRENT_IP)" | tee -a /var/log/macvlan-healthcheck.log
            CHANGED=1
        fi
    fi
done

mv "$STATE_FILE.new" "$STATE_FILE"

# IP 변경이 있으면 VPN 서버 재설정
if [ $CHANGED -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: VPN 서버 재설정 시작" | tee -a /var/log/macvlan-healthcheck.log

    # 기존 VPN 서버 중지
    for port in 55555 55556 55557 55558; do
        systemctl stop wg-quick@wg$port 2>/dev/null
    done

    # setup-vpn-per-ip.sh 실행하여 재설정
    if [ -f /home/vpn/setup-vpn-per-ip.sh ]; then
        /home/vpn/setup-vpn-per-ip.sh &>> /var/log/macvlan-healthcheck.log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: VPN 서버 재설정 완료" | tee -a /var/log/macvlan-healthcheck.log
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: /home/vpn/setup-vpn-per-ip.sh 없음" | tee -a /var/log/macvlan-healthcheck.log
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] OK: 모든 macvlan IP 정상" >> /var/log/macvlan-healthcheck.log
fi
