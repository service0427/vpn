#!/bin/bash

#######################################
# VPN 자동 추가 (SSH 기반)
# 사용법: ./add.sh root@서버IP wg0
#######################################

set -e

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 사용법
if [ $# -lt 2 ]; then
    echo "사용법: $0 <SSH접속정보> <인터페이스명>"
    echo ""
    echo "예시:"
    echo "  $0 root@112.161.221.9 wg0"
    echo "  $0 user@example.com wg1"
    exit 1
fi

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "root 권한 필요"
    exit 1
fi

SSH_HOST=$1
INTERFACE=$2

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}📡 VPN 자동 추가${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# SSH 연결 테스트
log_info "SSH 연결 테스트: $SSH_HOST"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 $SSH_HOST "exit" 2>/dev/null; then
    log_error "SSH 연결 실패. SSH 키 설정을 확인하세요"
    echo ""
    echo "SSH 키 설정 방법:"
    echo "  ssh-copy-id $SSH_HOST"
    exit 1
fi
log_success "SSH 연결 성공"

# 서버에서 설정 파일 다운로드
log_info "VPN 설정 다운로드 중..."
TEMP_FILE="/tmp/vpn-config-$INTERFACE.conf"

if ! ssh $SSH_HOST "cat /etc/wireguard/client.conf" > $TEMP_FILE 2>/dev/null; then
    log_error "설정 파일을 가져올 수 없습니다"
    log_info "서버에서 setup.sh를 먼저 실행했는지 확인하세요"
    rm -f $TEMP_FILE
    exit 1
fi

if [ ! -s "$TEMP_FILE" ]; then
    log_error "설정 파일이 비어있습니다"
    rm -f $TEMP_FILE
    exit 1
fi

log_success "설정 다운로드 완료"

# 설정 파일 복사 및 수정
TARGET_CONF="/etc/wireguard/${INTERFACE}.conf"
cp "$TEMP_FILE" "$TARGET_CONF"
chmod 600 "$TARGET_CONF"

# Table = off 추가 (수동 라우팅)
if ! grep -q "Table = off" "$TARGET_CONF"; then
    sed -i '/\[Interface\]/a Table = off' "$TARGET_CONF"
fi

# DNS 제거 (Rocky Linux 10 호환성)
sed -i '/^DNS/d' "$TARGET_CONF"

rm -f "$TEMP_FILE"

# VPN 시작
log_info "VPN 연결 시작: $INTERFACE"
systemctl enable wg-quick@${INTERFACE} 2>/dev/null
systemctl restart wg-quick@${INTERFACE}

if ! systemctl is-active --quiet wg-quick@${INTERFACE}; then
    log_error "VPN 시작 실패"
    journalctl -u wg-quick@${INTERFACE} -n 20 --no-pager
    exit 1
fi

log_success "VPN 연결 완료"

# 라우트 추가 (비활성 상태)
VPN_IP=$(grep "Address" "$TARGET_CONF" | head -n1 | cut -d'=' -f2 | cut -d'/' -f1 | tr -d ' ')
VPN_GATEWAY=$(echo $VPN_IP | sed 's/\.[0-9]*$/\.1/')

log_info "기본 라우트 추가 (metric 900 - 비활성)"
ip route add default via $VPN_GATEWAY dev $INTERFACE metric 900 2>/dev/null || true

# 완료
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN 추가 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📊 VPN 정보:${NC}"
echo "  - 인터페이스: $INTERFACE"
echo "  - VPN IP: $VPN_IP"
echo "  - 게이트웨이: $VPN_GATEWAY"
echo ""
echo -e "${BLUE}🔍 VPN 상태:${NC}"
wg show $INTERFACE 2>/dev/null | head -n 10
echo ""
echo -e "${GREEN}✅ 다음 단계:${NC}"
echo "  - VPN 활성화: sudo ./switch.sh 1"
echo "  - SSH 보호: sudo ./protect.sh"
echo "  - 연결 테스트: sudo ./test.sh"
echo ""
