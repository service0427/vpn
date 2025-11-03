#!/bin/bash

#######################################
# VPN 클라이언트 초기 설치 스크립트
# WireGuard 클라이언트 및 필요한 도구 설치
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

log_info "VPN 클라이언트 초기 설치를 시작합니다..."

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

# 필수 패키지 설치
log_info "필수 패키지 설치 중..."
$PKG_UPDATE

case $OS in
    rocky|centos|rhel|fedora)
        # Rocky Linux 10+는 iptables가 기본 설치 안됨
        $PKG_INSTALL wireguard-tools iproute curl iptables iptables-services jq
        ;;
    ubuntu|debian)
        $PKG_INSTALL wireguard-tools iproute2 curl iptables jq
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

log_success "WireGuard 및 필수 도구 설치 완료"

# WireGuard 디렉토리 생성
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# 헬퍼 스크립트 디렉토리
mkdir -p /usr/local/bin/vpn-tools
log_success "디렉토리 생성 완료"

# 스크립트 심볼릭 링크 생성
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_info "스크립트를 /usr/local/bin에 링크 중..."

# 주요 스크립트들 링크
for script in vpn sync.sh setup-vpnusers.sh; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        # 확장자 제거한 이름으로 링크
        link_name=$(basename "$script" .sh)
        ln -sf "$SCRIPT_DIR/$script" "/usr/local/bin/$link_name"
        log_success "링크 생성: /usr/local/bin/$link_name -> $SCRIPT_DIR/$script"
    fi
done

# sudoers 설정 (VPN 사용자 전환 시 비밀번호 불필요)
log_info "sudoers 설정 중..."
cat > /etc/sudoers.d/vpn-nopasswd << 'SUDOERS_EOF'
# VPN 사용자 전환 시 비밀번호 불필요
ALL ALL=(vpn0,vpn1,vpn2,vpn3,vpn4,vpn5,vpn6,vpn7,vpn8,vpn9) NOPASSWD: ALL
%wheel ALL=(vpn0,vpn1,vpn2,vpn3,vpn4,vpn5,vpn6,vpn7,vpn8,vpn9) NOPASSWD: ALL
SUDOERS_EOF
chmod 0440 /etc/sudoers.d/vpn-nopasswd
log_success "sudoers 설정 완료 (비밀번호 입력 불필요)"

# 완료 메시지
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN 클라이언트 초기 설치 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}✅ 다음 단계:${NC}"
echo "  1. sync          # VPN 목록 동기화 (API에서 자동 다운로드)"
echo "  2. setup-vpnusers # VPN 사용자 계정 생성"
echo "  3. vpn 0 curl ifconfig.me  # VPN 테스트"
echo ""
echo -e "${BLUE}💡 명령어 사용법:${NC}"
echo "  - sync: 어디서든 실행 가능 (VPN 목록 동기화)"
echo "  - vpn: 어디서든 실행 가능 (VPN으로 명령어 실행)"
echo "  - setup-vpnusers: 어디서든 실행 가능 (VPN 사용자 설정)"
echo ""
