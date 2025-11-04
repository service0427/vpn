#!/bin/bash

#######################################
# VPN Server Auto Install Script
# Automatically install and configure WireGuard VPN server
#######################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${BLUE}[정보]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[완료]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[경고]${NC} $1"
}

log_error() {
    echo -e "${RED}[오류]${NC} $1"
}

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    log_error "루트 권한이 필요합니다"
    exit 1
fi

# Check for existing VPN installation and remove automatically
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null || [ -f /etc/wireguard/wg0.conf ]; then
    log_warn "기존 VPN 설정 발견 - 자동 제거 후 재설치"

    # Stop service
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true

    # Remove configs
    rm -f /etc/wireguard/wg0.conf
    rm -f /etc/wireguard/server-private.key
    rm -f /etc/wireguard/server-public.key
    rm -f /etc/wireguard/client-private.key
    rm -f /etc/wireguard/client-public.key
    rm -f /etc/wireguard/client.conf

    log_success "기존 설정 제거 완료"
fi

log_info "VPN 서버 설치 시작..."

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    log_info "감지된 OS: $OS $VER"
else
    log_error "지원하지 않는 OS입니다"
    exit 1
fi

# Package manager setup
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

# Detect main network interface
log_info "네트워크 인터페이스 감지 중..."
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -z "$MAIN_INTERFACE" ]; then
    log_error "메인 네트워크 인터페이스를 찾을 수 없습니다"
    exit 1
fi
log_success "메인 인터페이스: $MAIN_INTERFACE"

# Get public IP
log_info "공인 IP 조회 중..."
PUBLIC_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "")
if [ -z "$PUBLIC_IP" ]; then
    log_error "공인 IP를 자동으로 감지할 수 없습니다"
    exit 1
fi
log_success "공인 IP: $PUBLIC_IP"

# Auto-generate VPN name from IP
VPN_NAME="vpn-$(echo $PUBLIC_IP | tr '.' '-')"
REGION="KR"

log_info "VPN 이름: $VPN_NAME"
log_info "지역: $REGION"

# Install WireGuard and required tools
log_info "WireGuard 및 필수 도구 설치 중..."
$PKG_UPDATE

case $OS in
    rocky|centos|rhel|fedora)
        $PKG_INSTALL wireguard-tools iptables iptables-services curl jq
        ;;
    ubuntu|debian)
        $PKG_INSTALL wireguard-tools curl jq
        ;;
esac

if ! command -v wg &> /dev/null; then
    log_error "WireGuard 설치 실패"
    exit 1
fi

log_success "WireGuard 및 필수 도구 설치 완료"

# Create WireGuard directory
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Generate server keys
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

# Generate client keys
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

# Create WireGuard server config
log_info "WireGuard 서버 설정 생성 중..."
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 55555
PrivateKey = $SERVER_PRIVATE_KEY

# IP forwarding and NAT
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

# Client config (multiple connections allowed with same key)
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.8.0.0/24
EOF

chmod 600 /etc/wireguard/wg0.conf
log_success "서버 설정 생성 완료"

# Enable IP forwarding permanently
log_info "IP 포워딩 활성화 중..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 > /dev/null
log_success "IP 포워딩 활성화 완료"

# Firewall rules (add rules without enabling firewall)
log_info "방화벽 안전 규칙 추가 중 (방화벽은 켜지 않음)..."

if command -v firewall-cmd &> /dev/null; then
    # firewalld 규칙 추가 (방화벽 켜지 않음)
    firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
    firewall-cmd --permanent --add-service=http 2>/dev/null || true
    firewall-cmd --permanent --add-service=https 2>/dev/null || true
    firewall-cmd --permanent --add-service=mysql 2>/dev/null || true
    firewall-cmd --permanent --add-service=postgresql 2>/dev/null || true
    firewall-cmd --permanent --add-port=55555/udp 2>/dev/null || true
    firewall-cmd --permanent --add-port=10000/tcp 2>/dev/null || true

    if systemctl is-active --quiet firewalld; then
        firewall-cmd --reload 2>/dev/null || true
        log_success "firewalld 규칙 추가 완료 (활성화 상태 유지)"
    else
        log_success "firewalld 규칙 추가 완료 (비활성화 상태 유지)"
    fi

elif command -v ufw &> /dev/null; then
    # UFW 규칙 추가 (방화벽 켜지 않음)
    ufw allow 22/tcp 2>/dev/null || true
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    ufw allow 3306/tcp 2>/dev/null || true
    ufw allow 5432/tcp 2>/dev/null || true
    ufw allow 55555/udp 2>/dev/null || true
    ufw allow 10000/tcp 2>/dev/null || true

    if ufw status | grep -q "Status: active"; then
        log_success "UFW 규칙 추가 완료 (활성화 상태 유지)"
    else
        log_success "UFW 규칙 추가 완료 (비활성화 상태 유지)"
    fi

else
    log_info "방화벽을 찾을 수 없습니다"
fi

log_info "💡 방화벽 상태는 변경하지 않았습니다 (SSH 안전)"

# Start WireGuard service
log_info "WireGuard 서비스 시작 중..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

if systemctl is-active --quiet wg-quick@wg0; then
    log_success "WireGuard 서비스 시작 완료"
else
    log_error "WireGuard 서비스 시작 실패"
    exit 1
fi

# Create client config file
CLIENT_CONFIG="/etc/wireguard/client.conf"
cat > $CLIENT_CONFIG <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.8.0.2/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:55555
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 $CLIENT_CONFIG

# Print completion message
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "VPN + SOCKS5 서버 설치 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}서버 정보:${NC}"
echo "  - 공인 IP: $PUBLIC_IP"
echo "  - VPN 서브넷: 10.8.0.0/24"
echo "  - 서버 주소: 10.8.0.1"
echo "  - 클라이언트 주소: 10.8.0.2 (기본값)"
echo ""
echo -e "${BLUE}클라이언트 설정 파일:${NC}"
echo "  위치: $CLIENT_CONFIG"
echo ""
echo -e "${YELLOW}이 설정 파일을 클라이언트 서버로 복사하세요!${NC}"
echo -e "${GREEN}💡 다중 접속:${NC} 여러 클라이언트에서 동일 키 사용 가능"
echo "   다른 클라이언트는 Address를 10.8.0.3, 10.8.0.4 등으로 변경하세요"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}클라이언트 설정 내용:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat $CLIENT_CONFIG
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${BLUE}VPN 상태:${NC}"
wg show
echo ""
echo -e "${GREEN}서비스 정보:${NC}"
echo "  [VPN 서버]"
echo "    - 프로토콜: WireGuard (UDP)"
echo "    - 포트: 55555"
echo "    - 접속: WireGuard 클라이언트 필요"
echo "    - 다중 접속: 동일 키로 여러 클라이언트 접속 가능"
echo ""
echo "  [SOCKS5 프록시]"
echo "    - 프로토콜: SOCKS5 with Auth (TCP)"
echo "    - 포트: 10000"
echo "    - 계정: techb:Tech1324"
echo "    - 접속: $PUBLIC_IP:10000"
echo "    - 다중 접속: 동시 접속 무제한"
echo ""
echo -e "${GREEN}다음 단계:${NC}"
echo "  1. 위의 클라이언트 설정을 복사"
echo "  2. 클라이언트 서버에서 setup.sh 실행"
echo "  3. add.sh로 설정 추가"
echo ""

# Register to API
log_info "API 서버에 등록 중..."
API_HOST="220.121.120.83"
API_ENDPOINT="/vpn_socks5/api/register.php"

# API call with debug output
log_info "API 호스트: $API_HOST"
log_info "공인 IP: $PUBLIC_IP"

# Prepare JSON payload with client config and SOCKS5 info
CLIENT_CONFIG_ESCAPED=$(cat $CLIENT_CONFIG | jq -Rs .)

API_PAYLOAD=$(cat <<EOF
{
    "public_ip": "$PUBLIC_IP",
    "port": 55555,
    "socks5_port": 10000,
    "socks5_username": "techb",
    "socks5_password": "Tech1324",
    "client_config": $CLIENT_CONFIG_ESCAPED
}
EOF
)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}전송할 데이터:${NC}"
echo "$API_PAYLOAD" | jq '.'
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://$API_HOST$API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}API 응답 (HTTP $HTTP_CODE):${NC}"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$HTTP_CODE" = "200" ] && echo "$BODY" | jq -e '.success' > /dev/null 2>&1; then
    log_success "API 등록 완료: $VPN_NAME"
else
    log_warn "API 등록 실패 (VPN은 정상 작동)"
    echo "디버그: API 서버 확인 http://$API_HOST/health"
fi

echo ""
echo -e "${BLUE}API 정보:${NC}"
echo "  - 공인 IP: $PUBLIC_IP"
echo "  - API 서버: $API_HOST"
echo ""

# Setup healthcheck cron
log_info "헬스체크 크론 설정 중..."
HEALTHCHECK_SCRIPT="/home/vpn/client/healthcheck.sh"

# healthcheck.sh가 없으면 생성
if [ ! -f "$HEALTHCHECK_SCRIPT" ]; then
    mkdir -p /home/vpn/client
    cat > $HEALTHCHECK_SCRIPT <<'HEALTHCHECK_EOF'
#!/bin/bash

#######################################
# VPN 헬스체크 스크립트
# 매분 실행하여 updated_at만 업데이트 (살아있음 표시)
#######################################

API_HOST="220.121.120.83"
API_ENDPOINT="/vpn_socks5/api/heartbeat.php"
LOG_FILE="/var/log/vpn-healthcheck.log"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "===== 헬스체크 시작 ====="

# 현재 서버의 공인 IP 확인
log "공인 IP 확인 중..."
MY_IP=$(curl -s -m 5 ifconfig.me 2>/dev/null || curl -s -m 5 api.ipify.org 2>/dev/null)

if [ -z "$MY_IP" ]; then
    log "❌ 공인 IP 확인 실패"
    exit 1
fi
log "✅ 공인 IP: $MY_IP"

# 로컬 WireGuard 인터페이스 확인 및 heartbeat 전송
FOUND=0
for wg_iface in $(ls /etc/wireguard/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//'); do
    log "인터페이스 체크: $wg_iface"

    # WireGuard 인터페이스가 실제로 떠있는지 확인
    if wg show "$wg_iface" > /dev/null 2>&1; then
        # 포트 확인
        PORT=$(grep "^ListenPort" /etc/wireguard/${wg_iface}.conf | awk '{print $3}' | tr -d ' ')

        if [ -n "$PORT" ]; then
            log "  → 포트: $PORT"

            # API를 통해 heartbeat 전송
            RESPONSE=$(curl -s -m 5 -X POST http://$API_HOST$API_ENDPOINT \
                -H "Content-Type: application/json" \
                -d "{\"public_ip\":\"$MY_IP\",\"port\":$PORT}" 2>&1)

            if echo "$RESPONSE" | grep -q '"success":true'; then
                log "  ✅ Heartbeat 성공: $MY_IP:$PORT"
                FOUND=1
            else
                log "  ❌ Heartbeat 실패: $RESPONSE"
            fi
        else
            log "  ⚠️  포트 정보 없음"
        fi
    else
        log "  ⚠️  인터페이스 비활성"
    fi
done

if [ $FOUND -eq 0 ]; then
    log "❌ 업데이트된 인터페이스 없음"
else
    log "✅ 헬스체크 완료"
fi
HEALTHCHECK_EOF
    chmod +x $HEALTHCHECK_SCRIPT
    log_success "healthcheck.sh 생성 완료"
fi

# crontab에 healthcheck 추가 (중복 방지)
CRON_LINE="*/1 * * * * $HEALTHCHECK_SCRIPT > /dev/null 2>&1"
if ! crontab -l 2>/dev/null | grep -qF "$HEALTHCHECK_SCRIPT"; then
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    log_success "헬스체크 크론 등록 완료 (매 1분)"
else
    log_info "헬스체크 크론이 이미 등록되어 있습니다"
fi

echo ""
echo -e "${GREEN}헬스체크:${NC}"
echo "  - 스크립트: $HEALTHCHECK_SCRIPT"
echo "  - 주기: 매 1분"
echo "  - 동작: 로컬 WireGuard 상태를 DB에 자동 업데이트"
echo ""

# Install Python3 if not present
log_info "Python3 확인 중..."
if ! command -v python3 &> /dev/null; then
    log_info "Python3 설치 중..."
    case $OS in
        rocky|centos|rhel|fedora)
            $PKG_INSTALL python3
            ;;
        ubuntu|debian)
            $PKG_INSTALL python3
            ;;
    esac
    log_success "Python3 설치 완료"
else
    log_success "Python3 이미 설치됨"
fi

# Setup SOCKS5 Proxy with Authentication
log_info "SOCKS5 프록시 설정 중..."
SOCKS5_DIR="/home/vpn/server"
SOCKS5_SCRIPT="$SOCKS5_DIR/socks5_auth.py"

# Create directory if not exists
mkdir -p "$SOCKS5_DIR"

# Create SOCKS5 server script
cat > $SOCKS5_SCRIPT <<'SOCKS5_EOF'
#!/usr/bin/env python3
"""
SOCKS5 Proxy Server with Username/Password Authentication
Port: 10000
Account: techb / Tech1324
"""

import socket
import select
import struct
import threading
import sys
import signal
import logging

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - SOCKS5 - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 하드코딩된 인증 정보
AUTH_USERNAME = b'techb'
AUTH_PASSWORD = b'Tech1324'

class SOCKS5Server:
    def __init__(self, port=10000):
        self.port = port
        self.running = True
        self.server_socket = None

    def start(self):
        """프록시 서버 시작"""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(128)
            logger.info(f"SOCKS5 proxy with auth listening on port {self.port}")

            while self.running:
                try:
                    readable, _, _ = select.select([self.server_socket], [], [], 1)
                    if readable:
                        client_socket, address = self.server_socket.accept()
                        thread = threading.Thread(target=self.handle_client, args=(client_socket, address))
                        thread.daemon = True
                        thread.start()
                except Exception as e:
                    if self.running:
                        logger.error(f"Error accepting connection: {e}")

        except Exception as e:
            logger.error(f"Failed to start server on port {self.port}: {e}")
        finally:
            self.stop()

    def handle_client(self, client_socket, address):
        """클라이언트 연결 처리"""
        try:
            # SOCKS5 버전 및 인증 방법 협상
            data = client_socket.recv(2)
            if len(data) < 2:
                client_socket.close()
                return

            version, nmethods = struct.unpack("!BB", data)
            if version != 5:
                client_socket.close()
                return

            # 클라이언트가 지원하는 인증 방법 읽기
            methods = client_socket.recv(nmethods)

            # 사용자명/비밀번호 인증 요구 (0x02)
            if b'\x02' not in methods:
                client_socket.send(b"\x05\xff")  # No acceptable methods
                client_socket.close()
                return

            client_socket.send(b"\x05\x02")  # Username/Password auth required

            # 사용자명/비밀번호 인증
            auth_data = client_socket.recv(2)
            if len(auth_data) < 2:
                client_socket.close()
                return

            auth_version, ulen = struct.unpack("!BB", auth_data)
            if auth_version != 1:
                client_socket.send(b"\x01\x01")  # Auth failed
                client_socket.close()
                return

            username = client_socket.recv(ulen)
            plen = struct.unpack("!B", client_socket.recv(1))[0]
            password = client_socket.recv(plen)

            # 인증 확인
            if username != AUTH_USERNAME or password != AUTH_PASSWORD:
                logger.warning(f"Auth failed from {address}: {username.decode('utf-8', errors='ignore')}")
                client_socket.send(b"\x01\x01")  # Auth failed
                client_socket.close()
                return

            logger.info(f"Auth success from {address}")
            client_socket.send(b"\x01\x00")  # Auth success

            # 연결 요청
            data = client_socket.recv(4)
            if len(data) < 4:
                client_socket.close()
                return

            version, cmd, _, atyp = struct.unpack("!BBBB", data)

            if cmd != 1:  # CONNECT only
                client_socket.send(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
                client_socket.close()
                return

            # 주소 파싱
            if atyp == 1:  # IPv4
                addr = socket.inet_ntoa(client_socket.recv(4))
            elif atyp == 3:  # Domain
                addr_len = client_socket.recv(1)[0]
                addr = client_socket.recv(addr_len).decode()
            else:
                client_socket.send(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
                client_socket.close()
                return

            port = struct.unpack("!H", client_socket.recv(2))[0]

            # 원격 서버 연결 (메인 이더넷 사용)
            try:
                remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                remote_socket.settimeout(10)
                remote_socket.connect((addr, port))

                # 성공 응답
                client_socket.send(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
                logger.debug(f"Connected to {addr}:{port}")

                # 데이터 중계
                self.relay_data(client_socket, remote_socket)

            except Exception as e:
                logger.debug(f"Failed to connect to {addr}:{port} - {e}")
                client_socket.send(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")

        except Exception as e:
            logger.debug(f"Error handling client: {e}")
        finally:
            client_socket.close()

    def relay_data(self, client_socket, remote_socket):
        """클라이언트와 원격 서버 간 데이터 중계"""
        try:
            client_socket.setblocking(False)
            remote_socket.setblocking(False)

            while self.running:
                ready = select.select([client_socket, remote_socket], [], [], 1)
                if ready[0]:
                    for sock in ready[0]:
                        data = sock.recv(4096)
                        if not data:
                            return
                        if sock is client_socket:
                            remote_socket.sendall(data)
                        else:
                            client_socket.sendall(data)
        except:
            pass
        finally:
            remote_socket.close()

    def stop(self):
        """서버 중지"""
        self.running = False
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
            logger.info(f"SOCKS5 proxy stopped on port {self.port}")

def main():
    server = SOCKS5Server(port=10000)

    def signal_handler(sig, frame):
        logger.info("Shutting down...")
        server.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    server.start()

if __name__ == '__main__':
    main()
SOCKS5_EOF

chmod +x $SOCKS5_SCRIPT
log_success "SOCKS5 스크립트 생성 완료: $SOCKS5_SCRIPT"

# Create systemd service for SOCKS5
log_info "SOCKS5 systemd 서비스 생성 중..."
cat > /etc/systemd/system/socks5-vpn.service <<EOF
[Unit]
Description=SOCKS5 Proxy Server with Authentication
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$SOCKS5_DIR
ExecStart=/usr/bin/python3 $SOCKS5_SCRIPT
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start SOCKS5 service
systemctl daemon-reload
systemctl enable socks5-vpn

# 기존 서비스가 실행 중이면 재시작, 아니면 시작
if systemctl is-active --quiet socks5-vpn; then
    log_info "SOCKS5 서비스 재시작 중..."
    systemctl restart socks5-vpn
else
    log_info "SOCKS5 서비스 시작 중..."
    systemctl start socks5-vpn
fi

if systemctl is-active --quiet socks5-vpn; then
    log_success "SOCKS5 서비스 시작 완료"
else
    log_error "SOCKS5 서비스 시작 실패"
    systemctl status socks5-vpn --no-pager
fi

echo ""
echo -e "${GREEN}SOCKS5 프록시:${NC}"
echo "  - 포트: 10000"
echo "  - 계정: techb:Tech1324"
echo "  - 주소: $PUBLIC_IP:10000"
echo "  - 인증: Username/Password (RFC1929)"
echo ""
