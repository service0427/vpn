#!/bin/bash

#######################################
# macvlan 인터페이스 생성 스크립트
# 메인 인터페이스에서 6개의 추가 IP 할당
#######################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "root 권한 필요"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🌐 macvlan 인터페이스 생성${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 메인 인터페이스
MAIN_IFACE="eno1"
MACVLAN_COUNT=6

log_info "메인 인터페이스: $MAIN_IFACE"
log_info "생성할 macvlan 수: $MACVLAN_COUNT"
echo ""

# 기존 macvlan 제거
log_info "기존 macvlan 인터페이스 제거 중..."
for i in $(seq 0 9); do
    if nmcli connection show macvlan$i &>/dev/null; then
        nmcli connection delete macvlan$i 2>/dev/null || true
        log_info "  macvlan$i 제거"
    fi
done
echo ""

# macvlan 인터페이스 생성
log_info "macvlan 인터페이스 생성 중..."
for i in $(seq 0 $((MACVLAN_COUNT - 1))); do
    MACVLAN_NAME="macvlan$i"

    log_info "[$MACVLAN_NAME] 생성 중..."

    # macvlan 인터페이스 생성
    nmcli connection add \
        type macvlan \
        ifname $MACVLAN_NAME \
        dev $MAIN_IFACE \
        mode bridge \
        con-name $MACVLAN_NAME \
        ipv4.method auto \
        ipv6.method disabled \
        connection.autoconnect yes \
        &>/dev/null

    if [ $? -eq 0 ]; then
        log_success "  [$MACVLAN_NAME] 생성 완료"
    else
        log_error "  [$MACVLAN_NAME] 생성 실패"
    fi
done
echo ""

# 인터페이스 활성화
log_info "macvlan 인터페이스 활성화 중..."
for i in $(seq 0 $((MACVLAN_COUNT - 1))); do
    MACVLAN_NAME="macvlan$i"
    nmcli connection up $MACVLAN_NAME &>/dev/null
    sleep 2  # DHCP IP 할당 대기
done
echo ""

# 할당된 IP 확인
log_info "DHCP IP 할당 대기 중... (최대 30초)"
sleep 10

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "macvlan 설정 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 결과 출력
echo -e "${BLUE}📊 할당된 IP 주소:${NC}"
echo ""
echo "메인 인터페이스:"
ip addr show $MAIN_IFACE | grep "inet " | awk '{print "  "$2}'
echo ""
echo "macvlan 인터페이스:"
for i in $(seq 0 $((MACVLAN_COUNT - 1))); do
    MACVLAN_NAME="macvlan$i"
    IP_ADDR=$(ip addr show $MACVLAN_NAME 2>/dev/null | grep "inet " | awk '{print $2}')
    if [ -n "$IP_ADDR" ]; then
        echo "  $MACVLAN_NAME: $IP_ADDR"
    else
        echo "  $MACVLAN_NAME: IP 할당 대기 중..."
    fi
done
echo ""

echo -e "${BLUE}💡 사용법:${NC}"
echo "  # 특정 IP로 bind하여 실행"
echo "  curl --interface macvlan0 https://ifconfig.me"
echo "  curl --interface macvlan1 https://ifconfig.me"
echo ""
echo -e "${GREEN}✅ 재부팅 시 자동 활성화됩니다${NC}"
echo ""
