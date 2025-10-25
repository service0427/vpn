#!/bin/bash

#######################################
# VPN 목록 동기화 (API 기반)
# 사용법: ./sync.sh
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

# API 정보
API_HOST="220.121.120.83"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔄 VPN 목록 동기화 (API)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# curl, jq 확인
if ! command -v curl &> /dev/null; then
    log_error "curl이 설치되지 않았습니다"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq가 설치되지 않았습니다"
    log_info "설치: dnf install -y jq (Rocky) 또는 apt install -y jq (Ubuntu)"
    exit 1
fi

# API 연결 테스트
log_info "API 연결 중: $API_HOST"
if ! curl -s -f http://$API_HOST/health > /dev/null; then
    log_error "API 연결 실패"
    exit 1
fi
log_success "API 연결 성공"

# VPN 목록 조회
log_info "VPN 목록 조회 중..."
VPN_LIST=$(curl -s http://$API_HOST/api/vpn/list)

VPN_COUNT=$(echo "$VPN_LIST" | jq '.vpns | length')

if [ "$VPN_COUNT" -eq 0 ]; then
    log_warn "활성 VPN이 없습니다"
    log_info "먼저 VPN 서버에서 setup.sh를 실행하세요"
    exit 0
fi

log_success "총 ${VPN_COUNT}개의 활성 VPN 발견"

# 기존 VPN 확인
EXISTING_VPNS=$(wg show interfaces 2>/dev/null || echo "")
if [ ! -z "$EXISTING_VPNS" ]; then
    log_warn "기존 VPN 인터페이스: $EXISTING_VPNS"
    read -p "기존 VPN을 모두 제거하고 다시 설정하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "동기화 취소됨"
        exit 0
    fi

    # 기존 VPN 제거
    for iface in $EXISTING_VPNS; do
        log_info "제거 중: $iface"
        systemctl stop wg-quick@${iface} 2>/dev/null || true
        systemctl disable wg-quick@${iface} 2>/dev/null || true
        rm -f /etc/wireguard/${iface}.conf
    done
fi

# VPN 추가
echo ""
log_info "VPN 추가 시작..."

echo "$VPN_LIST" | jq -r '.vpns[] | "\(.name)\t\(.host)\t\(.interface)"' | while IFS=$'\t' read -r name host interface; do
    echo ""
    log_info "[$name] 추가 중..."

    if ./add.sh "$host" "$interface"; then
        log_success "[$name] 추가 완료"
    else
        log_error "[$name] 추가 실패"
    fi
done

# setup-vpnusers.sh 실행
echo ""
log_info "VPN 사용자 설정 중..."
if [ -f "./setup-vpnusers.sh" ]; then
    ./setup-vpnusers.sh
else
    log_warn "setup-vpnusers.sh를 찾을 수 없습니다"
    log_info "수동으로 실행하세요: sudo ./setup-vpnusers.sh"
fi

# 완료
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN 동기화 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📊 설정된 VPN:${NC}"
wg show interfaces | tr ' ' '\n' | nl
echo ""
echo -e "${GREEN}✅ 사용법:${NC}"

# VPN별 사용자명 표시
for iface in $(wg show interfaces 2>/dev/null); do
    if [[ "$iface" =~ ^wg[0-9]+$ ]]; then
        NUM="${iface#wg}"
        USERNAME="vpn${NUM}"
    else
        USERNAME="vpn-${iface#wg-}"
    fi

    # API에서 VPN 이름 조회
    VPN_INFO=$(echo "$VPN_LIST" | jq -r ".vpns[] | select(.interface==\"$iface\") | .name")
    VPN_NAME=${VPN_INFO:-"unknown"}

    echo "  vpn $USERNAME python crawl.py  # $VPN_NAME ($iface)"
done

echo ""
