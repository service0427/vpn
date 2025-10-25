#!/bin/bash

#######################################
# VPN 서버 자동 설치 스크립트
# WireGuard VPN 서버를 자동으로 설치하고 설정
#######################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
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

log_info "VPN 서버 설치를 시작합니다..."

# OS 감지
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    log_info "감지된 OS: $OS $VER"
else
    log_error "지원하지 않는 OS입니다"
    exit 1
fi

# 패키지 관리자 설정
case $OS in
    ubuntu|debian)
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
        ;;
    rocky|centos|rhel|fedora)
        PKG_UPDATE="dnf check-update || true"
        PKG_INSTALL="dnf install -y"
        ;;
    *)
        log_error "지원하지 않는 OS: $OS"
        exit 1
        ;;
esac

# 메인 네트워크 인터페이스 감지
log_info "네트워크 인터페이스 감지 중..."
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTERFACE" ]; then
    log_error "메인 네트워크 인터페이스를 찾을 수 없습니다"
    exit 1
fi
log_success "메인 인터페이스: $MAIN_INTERFACE"

# 공인 IP 확인
log_info "공인 IP 확인 중..."
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
if [ -z "$PUBLIC_IP" ]; then
    log_warn "공인 IP를 자동으로 감지할 수 없습니다"
    read -p "서버의 공인 IP를 입력하세요: " PUBLIC_IP
fi
log_success "공인 IP: $PUBLIC_IP"

# WireGuard 및 필수 도구 설치
log_info "WireGuard 및 필수 도구 설치 중..."
$PKG_UPDATE

case $OS in
    rocky|centos|rhel|fedora)
        # Rocky Linux 10+는 iptables가 기본 설치 안됨
        $PKG_INSTALL wireguard-tools iptables iptables-services
        ;;
    ubuntu|debian)
        $PKG_INSTALL wireguard-tools iptables
        ;;
esac

if ! command -v wg &> /dev/null; then
    log_error "WireGuard 설치 실패"
    exit 1
fi

if ! command -v iptables &> /dev/null; then
    log_error "iptables 설치 실패"
    exit 1
fi

log_success "WireGuard 및 iptables 설치 완료"

# WireGuard 디렉토리 생성
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# 서버 키 생성
log_info "서버 키 생성 중..."
if [ ! -f /etc/wireguard/server-private.key ]; then
    wg genkey | tee /etc/wireguard/server-private.key | wg pubkey > /etc/wireguard/server-public.key
    chmod 600 /etc/wireguard/server-private.key
    log_success "서버 키 생성 완료"
else
    log_warn "서버 키가 이미 존재합니다 (재사용)"
fi

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server-private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server-public.key)

# 클라이언트 키 생성
log_info "클라이언트 키 생성 중..."
if [ ! -f /etc/wireguard/client-private.key ]; then
    wg genkey | tee /etc/wireguard/client-private.key | wg pubkey > /etc/wireguard/client-public.key
    chmod 600 /etc/wireguard/client-private.key
    log_success "클라이언트 키 생성 완료"
else
    log_warn "클라이언트 키가 이미 존재합니다 (재사용)"
fi

CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/client-private.key)
CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/client-public.key)

# WireGuard 서버 설정 파일 생성
log_info "WireGuard 서버 설정 파일 생성 중..."
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY

# IP 포워딩 및 NAT 설정
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

# 클라이언트 설정
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.2/32
EOF

chmod 600 /etc/wireguard/wg0.conf
log_success "서버 설정 파일 생성 완료"

# IP 포워딩 영구 활성화
log_info "IP 포워딩 영구 설정 중..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 > /dev/null
log_success "IP 포워딩 활성화 완료"

# 방화벽 설정
log_info "방화벽 설정 중..."
if command -v firewall-cmd &> /dev/null; then
    # firewalld (Rocky/CentOS/RHEL)
    log_info "firewalld 설정 중..."
    systemctl enable firewalld --now 2>/dev/null || true
    firewall-cmd --permanent --add-port=51820/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload
    log_success "firewalld 설정 완료"
elif command -v ufw &> /dev/null; then
    # UFW (Ubuntu/Debian)
    log_info "UFW 설정 중..."
    ufw allow 51820/udp
    ufw --force enable
    log_success "UFW 설정 완료"
else
    # iptables 직접 설정
    log_warn "방화벽을 찾을 수 없습니다 - iptables로 직접 설정"
    iptables -A INPUT -p udp --dport 51820 -j ACCEPT
    log_warn "iptables 규칙은 재부팅 시 사라질 수 있습니다"
fi

# WireGuard 서비스 시작
log_info "WireGuard 서비스 시작 중..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

if systemctl is-active --quiet wg-quick@wg0; then
    log_success "WireGuard 서비스 시작 완료"
else
    log_error "WireGuard 서비스 시작 실패"
    exit 1
fi

# 클라이언트 설정 파일 생성
CLIENT_CONFIG="/etc/wireguard/client.conf"
cat > $CLIENT_CONFIG <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.8.0.2/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 $CLIENT_CONFIG

# 완료 메시지
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN 서버 설치 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}📊 서버 정보:${NC}"
echo "  - 공인 IP: $PUBLIC_IP"
echo "  - VPN 서브넷: 10.8.0.0/24"
echo "  - 서버 주소: 10.8.0.1"
echo "  - 클라이언트 주소: 10.8.0.2"
echo ""
echo -e "${BLUE}📋 클라이언트 설정 파일:${NC}"
echo "  파일 위치: $CLIENT_CONFIG"
echo ""
echo -e "${YELLOW}⚠️  이 설정 파일을 클라이언트 서버로 복사하세요!${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}클라이언트 설정 파일 내용:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat $CLIENT_CONFIG
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}🔍 VPN 상태 확인:${NC}"
wg show
echo ""
echo -e "${GREEN}✅ 다음 단계:${NC}"
echo "  1. 위의 클라이언트 설정을 복사"
echo "  2. 클라이언트 서버에서 setup-vpn-client.sh 실행"
echo "  3. 복사한 설정으로 add-vpn.sh 실행"
echo ""
