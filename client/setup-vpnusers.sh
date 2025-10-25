#!/bin/bash

#######################################
# VPN 사용자 자동 생성 (UID 기반 라우팅)
# wg* 인터페이스를 자동 감지해서 vpn-{name} 사용자 생성
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
echo -e "${BLUE}👥 VPN 사용자 자동 생성${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# WireGuard 인터페이스 찾기
INTERFACES=$(wg show interfaces 2>/dev/null || echo "")

if [ -z "$INTERFACES" ]; then
    log_error "활성화된 WireGuard 인터페이스가 없습니다"
    log_info "먼저 VPN을 추가하세요: ./add.sh root@서버IP wg0"
    exit 1
fi

log_info "발견된 인터페이스: $INTERFACES"
echo ""

# 기존 라우팅 규칙 정리 (선택적)
log_info "기존 VPN 라우팅 규칙 정리 중..."
ip rule list | grep "lookup 10" | while read line; do
    PRIORITY=$(echo "$line" | awk '{print $1}' | tr -d ':')
    ip rule del priority $PRIORITY 2>/dev/null || true
done

# 각 인터페이스별로 사용자 생성
TABLE_ID=100
for iface in $INTERFACES; do
    # 인터페이스 이름에서 사용자명 생성
    # wg-kr1 → vpn-kr1
    # wg0 → vpn0
    USERNAME="vpn-${iface#wg-}"
    USERNAME="${USERNAME#vpn-wg}"  # wg0 → vpn-0 방지
    if [[ "$iface" =~ ^wg[0-9]+$ ]]; then
        # wg0, wg1 형식
        NUM="${iface#wg}"
        USERNAME="vpn${NUM}"
    else
        # wg-kr1 형식
        USERNAME="vpn-${iface#wg-}"
    fi

    log_info "[$iface] 사용자 생성: $USERNAME"

    # 사용자 생성 (이미 존재하면 스킵)
    if id "$USERNAME" &>/dev/null; then
        log_warn "  사용자 이미 존재: $USERNAME"
        UID=$(id -u $USERNAME)
    else
        useradd -m -s /bin/bash "$USERNAME" 2>/dev/null
        UID=$(id -u $USERNAME)
        log_success "  사용자 생성 완료 (UID: $UID)"
    fi

    # VPN 게이트웨이 IP 추출
    GATEWAY=$(ip route show dev $iface | grep "^10\." | awk '{print $1}' | awk -F'/' '{print $1}' | sed 's/\.0$/\.1/')

    if [ -z "$GATEWAY" ]; then
        log_error "  게이트웨이 IP를 찾을 수 없습니다: $iface"
        continue
    fi

    log_info "  게이트웨이: $GATEWAY"

    # 라우팅 테이블 설정
    log_info "  라우팅 테이블 설정 (table $TABLE_ID)..."

    # 기존 규칙 제거
    ip rule del uidrange $UID-$UID 2>/dev/null || true
    ip route flush table $TABLE_ID 2>/dev/null || true

    # 새 규칙 추가
    ip rule add uidrange $UID-$UID table $TABLE_ID priority 100
    ip route add default via $GATEWAY dev $iface table $TABLE_ID

    log_success "  [$iface] → [$USERNAME] 라우팅 설정 완료"
    echo ""

    TABLE_ID=$((TABLE_ID + 1))
done

# 영구 설정을 위한 systemd 서비스 생성
log_info "재부팅 시 자동 복구를 위한 서비스 생성 중..."
cat > /etc/systemd/system/vpn-routing.service <<EOF
[Unit]
Description=VPN UID-based Routing
After=network.target wg-quick.target

[Service]
Type=oneshot
ExecStart=$(readlink -f $0)
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn-routing.service 2>/dev/null
log_success "재부팅 시 자동 복구 설정 완료"

# 완료
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN 사용자 설정 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📊 생성된 사용자:${NC}"
for iface in $INTERFACES; do
    if [[ "$iface" =~ ^wg[0-9]+$ ]]; then
        NUM="${iface#wg}"
        USERNAME="vpn${NUM}"
    else
        USERNAME="vpn-${iface#wg-}"
    fi

    if id "$USERNAME" &>/dev/null; then
        UID=$(id -u $USERNAME)
        echo "  - $USERNAME (UID: $UID) → $iface"
    fi
done
echo ""
echo -e "${BLUE}🛣️  라우팅 규칙:${NC}"
ip rule list | grep "lookup 10"
echo ""
echo -e "${GREEN}✅ 사용법:${NC}"
echo "  sudo -u vpn0 python crawl.py"
echo "  sudo -u vpn1 curl https://naver.com"
echo ""
echo -e "${GREEN}💡 vpn wrapper 사용 (더 간편):${NC}"
echo "  vpn 0 python crawl.py"
echo "  vpn 1 curl https://naver.com"
echo ""
