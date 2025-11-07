#!/bin/bash

#====================================
# 동글 VPN (wg1) 설치 스크립트
# - 화웨이 동글을 통한 VPN 라우팅
# - 기존 서비스에 영향 없음
# - wg0과 독립적으로 동작
#====================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 기본 설정
VPN_INTERFACE="wg1"
VPN_PORT="51821"
VPN_SUBNET="10.0.1"
DONGLE_INTERFACE="enp0s21f0u4"  # 동글 인터페이스
SERVER_IP=$(curl -s ifconfig.me)
ROUTING_TABLE="201"

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   동글 VPN (wg1) 설치 스크립트${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}서버 IP: ${SERVER_IP}${NC}"
echo -e "${YELLOW}VPN 포트: ${VPN_PORT}${NC}"
echo -e "${YELLOW}VPN 서브넷: ${VPN_SUBNET}.0/24${NC}"
echo -e "${YELLOW}동글 인터페이스: ${DONGLE_INTERFACE}${NC}"
echo

# 동글 인터페이스 확인
if ! ip link show ${DONGLE_INTERFACE} &>/dev/null; then
    echo -e "${RED}❌ 동글 인터페이스 ${DONGLE_INTERFACE}를 찾을 수 없습니다${NC}"
    echo -e "${YELLOW}사용 가능한 인터페이스:${NC}"
    ip link show | grep -E "^[0-9]+" | awk '{print $2}' | sed 's/://g'
    echo
    read -p "동글 인터페이스 이름을 입력하세요: " DONGLE_INTERFACE
fi

# 동글 IP 확인
DONGLE_IP=$(ip -4 addr show ${DONGLE_INTERFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$DONGLE_IP" ]; then
    echo -e "${RED}❌ 동글 인터페이스에 IP가 할당되지 않았습니다${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 동글 IP: ${DONGLE_IP}${NC}"
echo

# 1. WireGuard 설치 확인
echo -e "${GREEN}[1/5] WireGuard 설치 확인...${NC}"
if ! command -v wg &> /dev/null; then
    echo -e "${YELLOW}WireGuard가 설치되어 있지 않습니다. 설치를 진행합니다...${NC}"

    # OS 감지
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    fi

    if [[ "$OS" == "ubuntu" ]]; then
        apt-get update && apt-get install -y wireguard-tools
    else
        dnf install -y epel-release && dnf install -y wireguard-tools
    fi
fi
echo -e "${GREEN}✓ WireGuard 설치 확인 완료${NC}"

# 2. 기존 wg1 설정 백업
if [ -f /etc/wireguard/${VPN_INTERFACE}.conf ]; then
    echo -e "${YELLOW}기존 wg1 설정 발견. 백업 중...${NC}"
    cp /etc/wireguard/${VPN_INTERFACE}.conf /etc/wireguard/${VPN_INTERFACE}.conf.bak.$(date +%Y%m%d_%H%M%S)
    wg-quick down ${VPN_INTERFACE} 2>/dev/null
fi

# 3. 서버 키 생성
echo -e "${GREEN}[2/5] 서버 키 생성...${NC}"
mkdir -p /etc/wireguard
cd /etc/wireguard

if [ ! -f ${VPN_INTERFACE}_server.key ]; then
    wg genkey | tee ${VPN_INTERFACE}_server.key | wg pubkey > ${VPN_INTERFACE}_server.pub
fi

SERVER_PRIVATE_KEY=$(cat ${VPN_INTERFACE}_server.key)
SERVER_PUBLIC_KEY=$(cat ${VPN_INTERFACE}_server.pub)

# 4. WireGuard 설정 파일 생성
echo -e "${GREEN}[3/5] WireGuard 설정 파일 생성...${NC}"
cat > /etc/wireguard/${VPN_INTERFACE}.conf << EOF
[Interface]
Address = ${VPN_SUBNET}.1/24
ListenPort = ${VPN_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}

# 라우팅 설정 - 동글을 통해서만 나가도록
Table = ${ROUTING_TABLE}

# 시작 시 실행
PostUp = ip rule add from ${VPN_SUBNET}.0/24 lookup ${ROUTING_TABLE}
PostUp = ip route add default dev ${DONGLE_INTERFACE} table ${ROUTING_TABLE}
PostUp = iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}.0/24 -o ${DONGLE_INTERFACE} -j MASQUERADE
PostUp = iptables -A FORWARD -i ${VPN_INTERFACE} -j ACCEPT
PostUp = iptables -A FORWARD -o ${VPN_INTERFACE} -j ACCEPT

# 종료 시 정리
PostDown = ip rule del from ${VPN_SUBNET}.0/24 lookup ${ROUTING_TABLE}
PostDown = ip route flush table ${ROUTING_TABLE}
PostDown = iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}.0/24 -o ${DONGLE_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${VPN_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -o ${VPN_INTERFACE} -j ACCEPT

EOF

# 5. 샘플 클라이언트 생성
echo -e "${GREEN}[4/5] 샘플 클라이언트 생성...${NC}"
mkdir -p /etc/wireguard/dongle_clients

for i in {2..5}; do
    CLIENT_IP="${VPN_SUBNET}.${i}"
    echo -e "  생성 중: ${CLIENT_IP}"

    # 클라이언트 키 생성
    CLIENT_PRIVATE=$(wg genkey)
    CLIENT_PUBLIC=$(echo ${CLIENT_PRIVATE} | wg pubkey)

    # 서버 설정에 Peer 추가
    cat >> /etc/wireguard/${VPN_INTERFACE}.conf << EOF
[Peer]
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32

EOF

    # 클라이언트 설정 파일 생성
    cat > /etc/wireguard/dongle_clients/client_${i}.conf << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = ${CLIENT_IP}/24
DNS = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${VPN_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
done

# 6. 방화벽 설정
echo -e "${GREEN}[5/5] 방화벽 설정...${NC}"

# OS 감지
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

if [[ "$OS" == "ubuntu" ]]; then
    ufw allow ${VPN_PORT}/udp
    echo -e "${GREEN}✓ UFW 방화벽에 포트 ${VPN_PORT}/udp 추가${NC}"
else
    firewall-cmd --permanent --add-port=${VPN_PORT}/udp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    echo -e "${GREEN}✓ firewalld에 포트 ${VPN_PORT}/udp 추가${NC}"
fi

# 7. WireGuard 시작
echo -e "${GREEN}WireGuard wg1 시작...${NC}"
wg-quick up ${VPN_INTERFACE}
systemctl enable wg-quick@${VPN_INTERFACE} 2>/dev/null

# 8. 설정 정보 저장
cat > /home/vpn/dongle_vpn_info.json << EOF
{
  "server": {
    "public_ip": "${SERVER_IP}",
    "port": ${VPN_PORT},
    "public_key": "${SERVER_PUBLIC_KEY}",
    "interface": "${VPN_INTERFACE}",
    "subnet": "${VPN_SUBNET}.0/24",
    "dongle_interface": "${DONGLE_INTERFACE}",
    "dongle_ip": "${DONGLE_IP}"
  },
  "routing": {
    "table": ${ROUTING_TABLE},
    "description": "모든 VPN 트래픽은 동글(${DONGLE_INTERFACE})을 통해 라우팅됩니다"
  }
}
EOF

# 9. 완료 메시지
echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   동글 VPN 설치 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}서버 정보:${NC}"
echo -e "  공인 IP: ${SERVER_IP}"
echo -e "  VPN 포트: ${VPN_PORT}"
echo -e "  서버 공개키: ${SERVER_PUBLIC_KEY}"
echo -e "  VPN 서브넷: ${VPN_SUBNET}.0/24"
echo -e "  동글 인터페이스: ${DONGLE_INTERFACE} (${DONGLE_IP})"
echo
echo -e "${YELLOW}라우팅 정보:${NC}"
echo -e "  모든 VPN 클라이언트 트래픽 → 동글(${DONGLE_INTERFACE}) → 인터넷"
echo
echo -e "${YELLOW}클라이언트 설정:${NC}"
echo -e "  /etc/wireguard/dongle_clients/ 폴더 확인"
echo
echo -e "${YELLOW}상태 확인:${NC}"
echo -e "  ${GREEN}wg show ${VPN_INTERFACE}${NC}"
echo
echo -e "${YELLOW}클라이언트 추가:${NC}"
echo -e "  ${GREEN}/home/vpn/add_dongle_client.sh${NC}"
echo

# 상태 표시
wg show ${VPN_INTERFACE}