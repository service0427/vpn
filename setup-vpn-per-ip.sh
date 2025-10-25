#!/bin/bash

#######################################
# macvlan IP별 VPN 서버 설정
# 각 IP마다 별도의 WireGuard 인스턴스 실행
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
echo -e "${BLUE}🌐 macvlan IP별 VPN 서버 설정${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

API_HOST="112.161.221.82"
BASE_PORT=55555

# macvlan IP 목록 (macvlan0-3만 사용)
MACVLAN_IPS=""
for i in 0 1 2 3; do
    IP=$(ip -4 addr show macvlan$i 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$IP" ]; then
        MACVLAN_IPS="$MACVLAN_IPS $IP"
    fi
done
MACVLAN_IPS=$(echo $MACVLAN_IPS | tr ' ' '\n')

if [ -z "$MACVLAN_IPS" ]; then
    log_error "macvlan IP가 없습니다"
    exit 1
fi

PORT=$BASE_PORT
for PUBLIC_IP in $MACVLAN_IPS; do
    echo ""
    log_info "[$PUBLIC_IP:$PORT] VPN 서버 설정 중..."

    # WireGuard 인터페이스 이름 (wgX 형식)
    WG_NAME="wg$PORT"
    SUBNET_THIRD=$((PORT - 55555))
    VPN_SUBNET="10.${SUBNET_THIRD}.0"

    mkdir -p /etc/wireguard

    # 키 생성
    if [ ! -f /etc/wireguard/${WG_NAME}-server-private.key ]; then
        wg genkey | tee /etc/wireguard/${WG_NAME}-server-private.key | wg pubkey > /etc/wireguard/${WG_NAME}-server-public.key
        chmod 600 /etc/wireguard/${WG_NAME}-server-private.key
    fi

    if [ ! -f /etc/wireguard/${WG_NAME}-client-private.key ]; then
        wg genkey | tee /etc/wireguard/${WG_NAME}-client-private.key | wg pubkey > /etc/wireguard/${WG_NAME}-client-public.key
        chmod 600 /etc/wireguard/${WG_NAME}-client-private.key
    fi

    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/${WG_NAME}-server-private.key)
    SERVER_PUBLIC_KEY=$(cat /etc/wireguard/${WG_NAME}-server-public.key)
    CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/${WG_NAME}-client-private.key)
    CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/${WG_NAME}-client-public.key)

    # 서버 설정 파일
    cat > /etc/wireguard/${WG_NAME}.conf <<EOF
[Interface]
Address = ${VPN_SUBNET}.1/24
ListenPort = $PORT
PrivateKey = $SERVER_PRIVATE_KEY

# Bind to specific IP
# Note: WireGuard will listen on this port on all IPs

# IP forwarding and NAT
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i ${WG_NAME} -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}.0/24 -j SNAT --to-source $PUBLIC_IP
PostDown = iptables -D FORWARD -i ${WG_NAME} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}.0/24 -j SNAT --to-source $PUBLIC_IP

# Client config
[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = ${VPN_SUBNET}.2/32
EOF

    chmod 600 /etc/wireguard/${WG_NAME}.conf

    # 클라이언트 설정 파일
    cat > /etc/wireguard/${WG_NAME}-client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = ${VPN_SUBNET}.2/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $PUBLIC_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    chmod 600 /etc/wireguard/${WG_NAME}-client.conf

    # 방화벽 설정
    firewall-cmd --permanent --add-port=$PORT/udp &>/dev/null || true

    # WireGuard 서비스 시작
    systemctl enable wg-quick@${WG_NAME} &>/dev/null
    systemctl restart wg-quick@${WG_NAME}

    if systemctl is-active --quiet wg-quick@${WG_NAME}; then
        log_success "  [$PUBLIC_IP:$PORT] VPN 서버 시작 완료"

        # API에 등록
        CLIENT_CONFIG=$(cat /etc/wireguard/${WG_NAME}-client.conf)
        CLIENT_CONFIG_ESCAPED=$(echo "$CLIENT_CONFIG" | jq -Rs .)

        API_RESPONSE=$(curl -s -X POST http://$API_HOST/api/vpn/register \
            -H "Content-Type: application/json" \
            -d "{\"public_ip\": \"$PUBLIC_IP\", \"port\": $PORT, \"client_config\": $CLIENT_CONFIG_ESCAPED}")

        if echo "$API_RESPONSE" | jq -e '.success' &>/dev/null; then
            log_success "  [$PUBLIC_IP:$PORT] API 등록 완료"
        else
            log_warn "  [$PUBLIC_IP:$PORT] API 등록 실패"
        fi
    else
        log_error "  [$PUBLIC_IP:$PORT] VPN 서버 시작 실패"
    fi

    PORT=$((PORT + 1))
done

# 방화벽 리로드
firewall-cmd --reload &>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "모든 VPN 서버 설정 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${BLUE}📊 설정된 VPN 서버:${NC}"
wg show | grep -E "interface:|listening port"
echo ""
