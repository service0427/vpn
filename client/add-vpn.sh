#!/bin/bash

#######################################
# VPN 연결 추가 스크립트
# 새로운 VPN 연결을 추가하고 설정
#######################################

set -e

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
if [ $# -lt 2 ]; then
    echo "사용법: $0 <인터페이스명> <설정파일>"
    echo ""
    echo "예시:"
    echo "  $0 wg0 /path/to/client.conf"
    echo "  $0 wg1 ~/vpn-config.conf"
    exit 1
fi

INTERFACE=$1
CONFIG_FILE=$2

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다"
    exit 1
fi

# 설정 파일 존재 확인
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
    exit 1
fi

log_info "VPN 연결 추가: $INTERFACE"

# 설정 파일 복사
TARGET_CONF="/etc/wireguard/${INTERFACE}.conf"
cp "$CONFIG_FILE" "$TARGET_CONF"
chmod 600 "$TARGET_CONF"
log_success "설정 파일 복사 완료: $TARGET_CONF"

# Table = off 설정 확인/추가 (수동 라우팅용)
if ! grep -q "Table = off" "$TARGET_CONF"; then
    sed -i '/\[Interface\]/a Table = off' "$TARGET_CONF"
    log_info "Table = off 설정 추가 (수동 라우팅)"
fi

# VPN 시작
log_info "VPN 연결 시작 중..."
systemctl enable wg-quick@${INTERFACE}
systemctl start wg-quick@${INTERFACE}

if systemctl is-active --quiet wg-quick@${INTERFACE}; then
    log_success "VPN 연결 시작 완료"
else
    log_error "VPN 연결 시작 실패"
    exit 1
fi

# VPN 게이트웨이 IP 추출
GATEWAY_IP=$(grep -A 10 "\[Peer\]" "$TARGET_CONF" | grep "Endpoint" | cut -d'=' -f2 | cut -d':' -f1 | tr -d ' ')
VPN_IP=$(grep "Address" "$TARGET_CONF" | head -n1 | cut -d'=' -f2 | cut -d'/' -f1 | tr -d ' ')

# VPN 서브넷에서 게이트웨이 주소 계산 (10.8.0.2 -> 10.8.0.1)
VPN_GATEWAY=$(echo $VPN_IP | sed 's/\.[0-9]*$/\.1/')

# 기본 라우트 추가 (metric 900 - 비활성)
log_info "기본 라우트 추가 (metric 900 - 비활성)..."
ip route add default via $VPN_GATEWAY dev $INTERFACE metric 900 2>/dev/null || true

# 상태 확인
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN 연결 추가 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📊 VPN 정보:${NC}"
echo "  - 인터페이스: $INTERFACE"
echo "  - VPN IP: $VPN_IP"
echo "  - 게이트웨이: $VPN_GATEWAY"
echo "  - 서버 IP: $GATEWAY_IP"
echo "  - Metric: 900 (비활성)"
echo ""
echo -e "${BLUE}🔍 VPN 상태:${NC}"
wg show $INTERFACE
echo ""
echo -e "${BLUE}🛣️  라우팅 테이블:${NC}"
ip route show | grep default
echo ""
echo -e "${GREEN}✅ 다음 단계:${NC}"
echo "  - VPN 활성화: ./switch-vpn.sh <번호>"
echo "  - SSH 보호: ./protect-ssh.sh"
echo "  - 연결 테스트: ./test-vpn.sh"
echo ""
