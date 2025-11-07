#!/bin/bash

#====================================
# VPN 서버 Heartbeat 스크립트
# - 1분마다 서버 상태를 중앙 API로 전송
# - 로그 없이 조용히 실행
#====================================

# 메인 네트워크 인터페이스 찾기 (default route 사용)
MAIN_INTERFACE=$(ip route | grep '^default' | head -1 | awk '{print $5}')

if [ -z "$MAIN_INTERFACE" ]; then
    # 메인 인터페이스를 찾지 못하면 종료
    exit 0
fi

# 메인 인터페이스에서 IP 주소 가져오기
SERVER_IP=$(ip -4 addr show $MAIN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

# 공인 IP가 필요한 경우 (사설 IP인 경우)
if [[ $SERVER_IP =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
    SERVER_IP=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || echo $SERVER_IP)
fi

# RX/TX 바이트 수집 (메인 이더넷 인터페이스)
RX=$(ip -s link show $MAIN_INTERFACE 2>/dev/null | grep -A1 "RX:" | tail -1 | awk '{print $1}')
TX=$(ip -s link show $MAIN_INTERFACE 2>/dev/null | grep -A1 "TX:" | tail -1 | awk '{print $1}')

# 기본값 설정
RX=${RX:-0}
TX=${TX:-0}

# Heartbeat 전송 (로그 없음)
curl -s --connect-timeout 5 "http://220.121.120.83/vpn_api/server/heartbeat?ip=$SERVER_IP&interface=$MAIN_INTERFACE&rx=$RX&tx=$TX" > /dev/null 2>&1

exit 0
