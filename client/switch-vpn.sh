#!/bin/bash

#######################################
# VPN 전환 스크립트
# VPN 연결을 전환하여 IP 롤링
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 사용법
if [ $# -lt 1 ]; then
    echo "사용법: $0 <VPN번호|인터페이스명|0>"
    echo ""
    echo "VPN 번호:"
    echo "  0  - 모든 VPN 비활성화 (메인 IP 사용)"
    echo "  1  - wg0 활성화"
    echo "  2  - wg1 활성화"
    echo "  3  - wg2 활성화"
    echo ""
    echo "인터페이스명:"
    echo "  wg0, wg1, wg2 등 직접 지정"
    echo ""
    echo "예시:"
    echo "  $0 1    # wg0 활성화"
    echo "  $0 wg1  # wg1 활성화"
    echo "  $0 0    # 모든 VPN 비활성화"
    exit 1
fi

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다"
    exit 1
fi

INPUT=$1
ACTIVE_INTERFACE=""

# 입력 파싱 (숫자 또는 인터페이스명)
if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
    # 숫자 입력
    VPN_NUM=$INPUT
    if [ $VPN_NUM -eq 0 ]; then
        ACTIVE_INTERFACE="none"
    else
        ACTIVE_INTERFACE="wg$((VPN_NUM-1))"
    fi
else
    # 인터페이스명 직접 입력
    ACTIVE_INTERFACE=$INPUT
fi

# 모든 WireGuard 인터페이스 찾기
ALL_INTERFACES=$(wg show interfaces 2>/dev/null || echo "")

if [ -z "$ALL_INTERFACES" ] && [ "$ACTIVE_INTERFACE" != "none" ]; then
    log_error "활성화된 WireGuard 인터페이스가 없습니다"
    log_info "먼저 add-vpn.sh로 VPN을 추가하세요"
    exit 1
fi

# 모든 VPN을 metric 900으로 설정 (비활성화)
log_info "모든 VPN을 비활성 상태로 설정..."
for iface in $ALL_INTERFACES; do
    # 기존 라우트 찾기
    GATEWAY=$(ip route show dev $iface | grep "^10\." | awk '{print $1}' | awk -F'/' '{print $1}' | sed 's/\.0$/\.1/')

    if [ ! -z "$GATEWAY" ]; then
        # 기존 default 라우트 제거
        ip route del default dev $iface 2>/dev/null || true

        # metric 900으로 재추가 (비활성)
        ip route add default via $GATEWAY dev $iface metric 900 2>/dev/null || true
        log_info "  $iface: metric 900 (비활성)"
    fi
done

# 선택한 VPN 활성화
if [ "$ACTIVE_INTERFACE" != "none" ]; then
    # 인터페이스 존재 확인
    if ! echo "$ALL_INTERFACES" | grep -q "$ACTIVE_INTERFACE"; then
        log_error "인터페이스를 찾을 수 없습니다: $ACTIVE_INTERFACE"
        log_info "사용 가능한 인터페이스: $ALL_INTERFACES"
        exit 1
    fi

    # 게이트웨이 주소 찾기
    GATEWAY=$(ip route show dev $ACTIVE_INTERFACE | grep "^10\." | awk '{print $1}' | awk -F'/' '{print $1}' | sed 's/\.0$/\.1/')

    if [ -z "$GATEWAY" ]; then
        log_error "게이트웨이 주소를 찾을 수 없습니다: $ACTIVE_INTERFACE"
        exit 1
    fi

    # 기존 라우트 제거
    ip route del default dev $ACTIVE_INTERFACE 2>/dev/null || true

    # metric 50으로 추가 (활성화)
    ip route add default via $GATEWAY dev $ACTIVE_INTERFACE metric 50

    log_success "$ACTIVE_INTERFACE 활성화 (metric 50)"
else
    log_success "모든 VPN 비활성화 - 메인 IP 사용"
fi

# 현재 상태 출력
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ VPN 전환 완료${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}🛣️  라우팅 테이블:${NC}"
ip route show | grep default | while read line; do
    if echo "$line" | grep -q "metric 50"; then
        echo -e "  ${GREEN}✓${NC} $line  ${GREEN}← 활성${NC}"
    else
        echo -e "    $line"
    fi
done
echo ""

# VPN 상태
if [ "$ACTIVE_INTERFACE" != "none" ]; then
    echo -e "${BLUE}🔍 활성 VPN 상태:${NC}"
    wg show $ACTIVE_INTERFACE 2>/dev/null | head -n 10
    echo ""
fi

# 외부 IP 확인 (백그라운드로 실행)
echo -e "${BLUE}🌍 외부 IP 확인 중...${NC}"
EXTERNAL_IP=$(timeout 3 curl -s ifconfig.me 2>/dev/null || echo "확인 실패")
if [ "$EXTERNAL_IP" != "확인 실패" ]; then
    echo -e "  현재 외부 IP: ${GREEN}$EXTERNAL_IP${NC}"
else
    echo -e "  ${YELLOW}외부 IP 확인 실패 (인터넷 연결 확인)${NC}"
fi
echo ""

echo -e "${GREEN}✅ curl-cffi, playwright 등이 자동으로 이 VPN을 사용합니다${NC}"
echo ""
