#!/bin/bash

#######################################
# VPN 연결 추가 (Interactive 버전)
# 서버 설정을 복사-붙여넣기로 간편하게 추가
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

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📝 VPN 설정 추가 (Interactive)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 인터페이스명 입력
read -p "인터페이스명 (예: wg0, wg1): " INTERFACE
if [ -z "$INTERFACE" ]; then
    log_error "인터페이스명을 입력하세요"
    exit 1
fi

# 설정 방법 선택
echo ""
echo -e "${YELLOW}설정 입력 방법을 선택하세요:${NC}"
echo "  1) 서버 설정을 복사-붙여넣기 (권장)"
echo "  2) 설정 파일 경로 입력"
echo ""
read -p "선택 [1-2]: " METHOD

case $METHOD in
    1)
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}서버에서 출력된 [Interface]부터 끝까지 붙여넣으세요${NC}"
        echo -e "${GREEN}붙여넣기 후 Ctrl+D를 누르세요${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        # 임시 파일에 저장
        TEMP_FILE="/tmp/vpn-config-$INTERFACE.conf"
        cat > "$TEMP_FILE"

        if [ ! -s "$TEMP_FILE" ]; then
            log_error "설정이 비어있습니다"
            rm -f "$TEMP_FILE"
            exit 1
        fi

        CONFIG_FILE="$TEMP_FILE"
        ;;
    2)
        read -p "설정 파일 경로: " CONFIG_FILE
        if [ ! -f "$CONFIG_FILE" ]; then
            log_error "파일을 찾을 수 없습니다: $CONFIG_FILE"
            exit 1
        fi
        ;;
    *)
        log_error "잘못된 선택"
        exit 1
        ;;
esac

log_info "VPN 연결 추가: $INTERFACE"

# 설정 파일 복사
TARGET_CONF="/etc/wireguard/${INTERFACE}.conf"
cp "$CONFIG_FILE" "$TARGET_CONF"
chmod 600 "$TARGET_CONF"
log_success "설정 파일 복사 완료: $TARGET_CONF"

# Table = off 설정 확인/추가
if ! grep -q "Table = off" "$TARGET_CONF"; then
    sed -i '/\[Interface\]/a Table = off' "$TARGET_CONF"
    log_info "Table = off 설정 추가 (수동 라우팅)"
fi

# DNS 설정 제거 (systemd-resolved 없을 경우 문제 발생)
# DNS는 선택사항이므로 제거해도 무방
if grep -q "^DNS" "$TARGET_CONF"; then
    sed -i '/^DNS/d' "$TARGET_CONF"
    log_info "DNS 설정 제거 (호환성)"
fi

# 임시 파일 삭제
if [ "$METHOD" == "1" ]; then
    rm -f "$TEMP_FILE"
fi

# VPN 시작
log_info "VPN 연결 시작 중..."
systemctl enable wg-quick@${INTERFACE}
systemctl start wg-quick@${INTERFACE}

if systemctl is-active --quiet wg-quick@${INTERFACE}; then
    log_success "VPN 연결 시작 완료"
else
    log_error "VPN 연결 시작 실패"
    journalctl -u wg-quick@${INTERFACE} -n 20
    exit 1
fi

# VPN 게이트웨이 IP 추출
GATEWAY_IP=$(grep -A 10 "\[Peer\]" "$TARGET_CONF" | grep "Endpoint" | cut -d'=' -f2 | cut -d':' -f1 | tr -d ' ')
VPN_IP=$(grep "Address" "$TARGET_CONF" | head -n1 | cut -d'=' -f2 | cut -d'/' -f1 | tr -d ' ')
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
echo -e "${GREEN}✅ 다음 단계:${NC}"
echo "  - VPN 활성화: sudo ./switch-vpn.sh 1"
echo "  - SSH 보호: sudo ./protect-ssh.sh"
echo "  - 연결 테스트: sudo ./test-vpn.sh"
echo ""
