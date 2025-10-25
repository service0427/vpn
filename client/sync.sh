#!/bin/bash

#######################################
# VPN 목록 동기화 (DB 기반)
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

# DB 정보
DB_HOST="220.121.120.83"
DB_USER="vpnuser"
DB_PASS="vpn1324"
DB_NAME="vpn"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}🔄 VPN 목록 동기화 (DB)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# MySQL 클라이언트 확인
if ! command -v mysql &> /dev/null; then
    log_error "MySQL 클라이언트가 설치되지 않았습니다"
    log_info "설치: dnf install -y mysql (Rocky) 또는 apt install -y mysql-client (Ubuntu)"
    exit 1
fi

# DB 연결 테스트
log_info "DB 연결 중: $DB_HOST"
if ! mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" -D $DB_NAME -e "SELECT 1" &>/dev/null; then
    log_error "DB 연결 실패"
    exit 1
fi
log_success "DB 연결 성공"

# VPN 목록 조회
log_info "VPN 목록 조회 중..."
VPN_COUNT=$(mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" -D $DB_NAME -sN -e "SELECT COUNT(*) FROM vpn_servers WHERE status='active'" 2>/dev/null)

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

# DB에서 VPN 목록 가져와서 처리
mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" -D $DB_NAME -sN << 'EOSQL' | while IFS=$'\t' read -r name host interface; do
SELECT name, host, interface
FROM vpn_servers
WHERE status = 'active'
ORDER BY created_at;
EOSQL
    echo ""
    log_info "[$name] 추가 중..."

    if ./add.sh "$host" "$interface"; then
        log_success "[$name] 추가 완료"
    else
        log_error "[$name] 추가 실패"
    fi
done 2>/dev/null

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

    # DB에서 VPN 이름 조회
    VPN_NAME=$(mysql -h $DB_HOST -u $DB_USER -p"$DB_PASS" -D $DB_NAME -sN -e "SELECT name FROM vpn_servers WHERE interface='$iface' LIMIT 1" 2>/dev/null || echo "unknown")

    echo "  vpn $USERNAME python crawl.py  # $VPN_NAME ($iface)"
done 2>/dev/null

echo ""
