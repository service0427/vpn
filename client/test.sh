#!/bin/bash

#######################################
# VPN 연결 테스트 스크립트
# VPN 상태 및 연결을 종합적으로 테스트
#######################################

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔍 VPN 연결 테스트${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. WireGuard 인터페이스 확인
echo -e "${BLUE}1️⃣  WireGuard 인터페이스 확인${NC}"
INTERFACES=$(wg show interfaces 2>/dev/null || echo "")

if [ -z "$INTERFACES" ]; then
    log_error "WireGuard 인터페이스가 없습니다"
    log_info "add-vpn.sh로 VPN을 먼저 추가하세요"
    exit 1
fi

for iface in $INTERFACES; do
    if systemctl is-active --quiet wg-quick@${iface}; then
        log_success "$iface (활성)"
    else
        log_error "$iface (비활성)"
    fi
done
echo ""

# 2. VPN 연결 상태 확인 (Handshake)
echo -e "${BLUE}2️⃣  VPN 연결 상태 (Handshake)${NC}"
for iface in $INTERFACES; do
    echo -e "  ${BLUE}$iface:${NC}"
    HANDSHAKE=$(wg show $iface latest-handshakes 2>/dev/null | awk '{print $2}')

    if [ ! -z "$HANDSHAKE" ] && [ "$HANDSHAKE" != "0" ]; then
        SECONDS_AGO=$(($(date +%s) - $HANDSHAKE))
        if [ $SECONDS_AGO -lt 180 ]; then
            log_success "연결됨 (${SECONDS_AGO}초 전)"
        else
            log_warn "연결됨 (${SECONDS_AGO}초 전 - 오래됨)"
        fi
    else
        log_error "연결 안됨 (handshake 없음)"
    fi
done
echo ""

# 3. 라우팅 테이블 확인
echo -e "${BLUE}3️⃣  라우팅 테이블${NC}"
ACTIVE_VPN=""
ip route show | grep default | while read line; do
    if echo "$line" | grep -q "metric 50"; then
        echo -e "  ${GREEN}✓${NC} $line  ${GREEN}← 활성${NC}"
        ACTIVE_VPN=$(echo "$line" | grep -oP 'dev \K\w+')
    elif echo "$line" | grep -q "wg"; then
        echo -e "    $line  ${YELLOW}(비활성)${NC}"
    else
        echo -e "    $line  ${BLUE}(메인)${NC}"
    fi
done
echo ""

# 4. 현재 외부 IP 확인
echo -e "${BLUE}4️⃣  외부 IP 확인${NC}"
echo -n "  확인 중... "
EXTERNAL_IP=$(timeout 5 curl -s ifconfig.me 2>/dev/null || timeout 5 curl -s icanhazip.com 2>/dev/null || echo "")

if [ ! -z "$EXTERNAL_IP" ]; then
    echo -e "${GREEN}$EXTERNAL_IP${NC}"

    # VPN이 활성화되어 있으면 VPN 서버 IP와 비교
    ACTIVE_VPN=$(ip route show | grep "default.*metric 50" | grep -oP 'dev \K\w+')
    if [ ! -z "$ACTIVE_VPN" ]; then
        VPN_SERVER=$(grep Endpoint /etc/wireguard/${ACTIVE_VPN}.conf 2>/dev/null | cut -d'=' -f2 | cut -d':' -f1 | tr -d ' ')
        if [ "$EXTERNAL_IP" == "$VPN_SERVER" ]; then
            log_success "VPN IP와 일치 ✓"
        else
            log_warn "VPN 서버 IP: $VPN_SERVER (외부 IP와 다름)"
        fi
    fi
else
    log_error "확인 실패 (인터넷 연결 확인)"
fi
echo ""

# 5. DNS 확인
echo -e "${BLUE}5️⃣  DNS 확인${NC}"
if timeout 3 nslookup google.com > /dev/null 2>&1; then
    log_success "DNS 작동 중"
else
    log_error "DNS 실패"
fi
echo ""

# 6. 인터넷 연결 테스트
echo -e "${BLUE}6️⃣  인터넷 연결 테스트${NC}"
if timeout 5 curl -s https://www.google.com > /dev/null 2>&1; then
    log_success "인터넷 연결 정상"
else
    log_error "인터넷 연결 실패"
fi
echo ""

# 7. SSH 보호 확인
echo -e "${BLUE}7️⃣  SSH 보호 확인${NC}"
MAIN_IP=$(ip route | grep default | grep -v wg | awk '{print $3}' | head -n1)
if ip rule show | grep -q "from.*table main"; then
    log_success "SSH 보호 활성화됨"
else
    log_warn "SSH 보호 미설정 (./protect-ssh.sh 실행 권장)"
fi
echo ""

# 8. 전송 통계
echo -e "${BLUE}8️⃣  전송 통계${NC}"
for iface in $INTERFACES; do
    echo -e "  ${BLUE}$iface:${NC}"
    TRANSFER=$(wg show $iface transfer 2>/dev/null)
    if [ ! -z "$TRANSFER" ]; then
        RX=$(echo "$TRANSFER" | awk '{print $2}')
        TX=$(echo "$TRANSFER" | awk '{print $3}')

        # 바이트를 읽기 쉬운 형식으로 변환
        RX_MB=$(echo "scale=2; $RX / 1048576" | bc 2>/dev/null || echo "0")
        TX_MB=$(echo "scale=2; $TX / 1048576" | bc 2>/dev/null || echo "0")

        echo -e "    수신: ${GREEN}${RX_MB} MB${NC}"
        echo -e "    송신: ${GREEN}${TX_MB} MB${NC}"
    else
        log_warn "통계 없음"
    fi
done
echo ""

# 요약
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ 테스트 완료${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}💡 다음 단계:${NC}"
echo "  - VPN 전환: ./switch-vpn.sh <번호>"
echo "  - Python 테스트: python3 -c \"import requests; print(requests.get('https://ifconfig.me').text)\""
echo ""
