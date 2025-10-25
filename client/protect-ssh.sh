#!/bin/bash

#######################################
# SSH 보호 스크립트
# Policy routing으로 SSH가 항상 메인 IP를 사용하도록 설정
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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Root 권한 확인
if [ "$EUID" -ne 0 ]; then
    log_error "이 스크립트는 root 권한이 필요합니다"
    exit 1
fi

log_info "SSH 보호 설정을 시작합니다..."

# 메인 인터페이스 감지
MAIN_INTERFACE=$(ip route | grep default | grep -v "wg" | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTERFACE" ]; then
    log_error "메인 네트워크 인터페이스를 찾을 수 없습니다"
    exit 1
fi
log_info "메인 인터페이스: $MAIN_INTERFACE"

# 메인 IP 감지
MAIN_IP=$(ip addr show $MAIN_INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1)
if [ -z "$MAIN_IP" ]; then
    log_error "메인 IP를 찾을 수 없습니다"
    exit 1
fi
log_info "메인 IP: $MAIN_IP"

# 기존 규칙 확인
if ip rule show | grep -q "from $MAIN_IP"; then
    log_warn "SSH 보호 규칙이 이미 존재합니다 (재설정)"
    # 기존 규칙 제거
    ip rule del from $MAIN_IP table main 2>/dev/null || true
fi

# Policy routing 규칙 추가
log_info "Policy routing 규칙 추가 중..."

# 출발지 IP가 메인 IP인 트래픽은 메인 라우팅 테이블 사용 (우선순위 100)
ip rule add from $MAIN_IP table main priority 100

log_success "Policy routing 규칙 추가 완료"

# SSH 포트 확인
SSH_PORT=$(ss -tlnp | grep sshd | grep -oP ':\K[0-9]+' | head -n1 || echo "22")
log_info "SSH 포트: $SSH_PORT"

# 재부팅 후에도 유지되도록 설정
log_info "재부팅 후에도 유지되도록 설정 중..."

# systemd 서비스 파일 생성
cat > /etc/systemd/system/vpn-ssh-protect.service <<EOF
[Unit]
Description=VPN SSH Protection
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ip rule add from $MAIN_IP table main priority 100
RemainAfterExit=yes
ExecStop=/sbin/ip rule del from $MAIN_IP table main priority 100

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vpn-ssh-protect.service
log_success "systemd 서비스 등록 완료"

# 테스트
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "SSH 보호 설정 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📊 설정 정보:${NC}"
echo "  - 메인 IP: $MAIN_IP"
echo "  - 메인 인터페이스: $MAIN_INTERFACE"
echo "  - SSH 포트: $SSH_PORT"
echo ""
echo -e "${BLUE}🛡️  Policy Routing 규칙:${NC}"
ip rule show | grep -A1 -B1 "$MAIN_IP"
echo ""
echo -e "${GREEN}✅ SSH 연결은 항상 메인 IP를 사용합니다${NC}"
echo -e "${GREEN}✅ VPN 전환 시에도 SSH가 끊기지 않습니다${NC}"
echo ""
echo -e "${YELLOW}⚠️  테스트:${NC}"
echo "  1. VPN을 활성화하세요: ./switch-vpn.sh 1"
echo "  2. SSH가 여전히 연결되어 있는지 확인"
echo "  3. 새로운 SSH 연결이 가능한지 확인"
echo ""
