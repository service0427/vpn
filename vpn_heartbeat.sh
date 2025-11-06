#!/bin/bash

#====================================
# VPN 서버 Heartbeat 스크립트
# - 1분마다 서버 상태를 중앙 API로 전송
# - 로그 없이 조용히 실행
#====================================

SERVER_IP=$(curl -s ifconfig.me)
INTERFACE="wg0"

# WireGuard 인터페이스가 활성화되어 있는지 확인
if ! ip link show $INTERFACE > /dev/null 2>&1; then
    # 인터페이스가 없으면 조용히 종료
    exit 0
fi

# RX/TX 바이트 수집
RX=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo "0")
TX=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo "0")

# Heartbeat 전송 (로그 없음)
curl -s "http://220.121.120.83/vpn_api/server/heartbeat?ip=$SERVER_IP&interface=$INTERFACE&rx=$RX&tx=$TX" > /dev/null 2>&1

exit 0
