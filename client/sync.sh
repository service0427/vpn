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
API_BASE="/vpn_socks5/api"

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
if ! curl -s -f http://$API_HOST$API_BASE/test_db.php > /dev/null 2>&1; then
    log_warn "API 헬스체크 실패 (계속 진행)"
fi
log_success "API 연결 성공"

# VPN 목록 조회
log_info "VPN 목록 조회 중..."
VPN_LIST=$(curl -s http://$API_HOST$API_BASE/servers.php?active=true)

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

VPN_INDEX=0
echo "$VPN_LIST" | jq -r '.vpns[] | "\(.public_ip):\(.port)"' | while IFS=: read -r public_ip port; do
    echo ""
    # 간단한 인터페이스 이름 사용 (wg0, wg1, wg2, ...)
    INTERFACE="wg${VPN_INDEX}"
    log_info "[$public_ip:$port] → $INTERFACE 추가 중..."

    # API에서 클라이언트 설정 다운로드
    TEMP_FILE="/tmp/vpn-config-${INTERFACE}.conf"

    if ! curl -s -f "http://$API_HOST$API_BASE/config.php?ip=$public_ip&port=$port" > "$TEMP_FILE"; then
        log_error "[$public_ip:$port] 설정 다운로드 실패"
        rm -f "$TEMP_FILE"
        VPN_INDEX=$((VPN_INDEX + 1))
        continue
    fi

    if [ ! -s "$TEMP_FILE" ]; then
        log_error "[$public_ip] 설정 파일이 비어있습니다"
        rm -f "$TEMP_FILE"
        VPN_INDEX=$((VPN_INDEX + 1))
        continue
    fi

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
    systemctl enable wg-quick@${INTERFACE} 2>/dev/null
    systemctl restart wg-quick@${INTERFACE}

    if systemctl is-active --quiet wg-quick@${INTERFACE}; then
        log_success "[$public_ip] → $INTERFACE 추가 완료"

        # 라우트 추가 (비활성 상태)
        VPN_IP=$(grep "Address" "$TARGET_CONF" | head -n1 | cut -d'=' -f2 | cut -d'/' -f1 | tr -d ' ')
        VPN_GATEWAY=$(echo $VPN_IP | awk -F'.' '{print $1"."$2"."$3".1"}')
        ip route add default via $VPN_GATEWAY dev $INTERFACE metric 900 2>/dev/null || true
    else
        log_error "[$public_ip] → $INTERFACE VPN 시작 실패"
        journalctl -u wg-quick@${INTERFACE} -n 10 --no-pager
    fi

    VPN_INDEX=$((VPN_INDEX + 1))
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
IDX=0
for iface in $(wg show interfaces 2>/dev/null); do
    if [[ "$iface" =~ ^wg[0-9]+$ ]]; then
        NUM="${iface#wg}"
    else
        NUM="$IDX"
    fi

    # API에서 VPN IP 조회
    VPN_IP_INFO=$(echo "$VPN_LIST" | jq -r ".vpns[$IDX].public_ip // \"unknown\"")
    VPN_PUBLIC_IP=${VPN_IP_INFO:-"unknown"}

    echo "  ./vpn $NUM curl ifconfig.me  # $VPN_PUBLIC_IP ($iface → vpn$NUM)"
    IDX=$((IDX + 1))
done

echo ""
