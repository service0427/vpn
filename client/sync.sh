#!/bin/bash

#######################################
# VPN 목록 동기화 (API 기반)
# 사용법: ./sync.sh <JSON_URL>
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

# 사용법
if [ $# -lt 1 ]; then
    echo "사용법: $0 <JSON_URL>"
    echo ""
    echo "예시:"
    echo "  $0 http://112.161.221.9:8080/vpn-list.json"
    echo "  $0 https://api.yourserver.com/vpn-list.json"
    exit 1
fi

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "root 권한 필요"
    exit 1
fi

JSON_URL=$1

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔄 VPN 목록 동기화${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# JSON 다운로드
log_info "VPN 목록 다운로드 중..."
TEMP_JSON="/tmp/vpn-list.json"

if ! curl -sf -o "$TEMP_JSON" "$JSON_URL"; then
    log_error "JSON 다운로드 실패: $JSON_URL"
    exit 1
fi

# JSON 유효성 검사
if ! python3 -m json.tool "$TEMP_JSON" > /dev/null 2>&1; then
    log_error "잘못된 JSON 형식"
    rm -f "$TEMP_JSON"
    exit 1
fi

log_success "VPN 목록 다운로드 완료"

# VPN 개수 확인
VPN_COUNT=$(python3 -c "import json; print(len(json.load(open('$TEMP_JSON'))['vpns']))")
log_info "총 ${VPN_COUNT}개의 VPN 발견"

# 기존 VPN 인터페이스 백업
EXISTING_VPNS=$(wg show interfaces 2>/dev/null || echo "")
if [ ! -z "$EXISTING_VPNS" ]; then
    log_warn "기존 VPN 인터페이스: $EXISTING_VPNS"
    read -p "기존 VPN을 모두 제거하고 다시 설정하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "동기화 취소됨"
        rm -f "$TEMP_JSON"
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

python3 << 'EOPY'
import json
import sys

with open('/tmp/vpn-list.json') as f:
    data = json.load(f)

for vpn in data['vpns']:
    print(f"{vpn['name']}|{vpn['host']}|{vpn['interface']}")
EOPY

python3 << 'EOPY' > /tmp/vpn-commands.sh
import json

with open('/tmp/vpn-list.json') as f:
    data = json.load(f)

print("#!/bin/bash")
for i, vpn in enumerate(data['vpns']):
    name = vpn['name']
    host = vpn['host']
    iface = vpn['interface']
    print(f"echo ''; echo '[{i+1}/{len(data['vpns'])}] {name} 추가 중...'")
    print(f"./add.sh {host} {iface} || echo 'FAILED: {name}'")
EOPY

chmod +x /tmp/vpn-commands.sh
bash /tmp/vpn-commands.sh

rm -f /tmp/vpn-commands.sh

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
wg show interfaces
echo ""
echo -e "${GREEN}✅ 사용법:${NC}"
echo "  vpn korea1 python crawl.py"
echo "  vpn korea2 curl https://naver.com"
echo ""

rm -f "$TEMP_JSON"
