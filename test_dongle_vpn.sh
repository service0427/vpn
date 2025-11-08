#!/bin/bash

#====================================
# 동글 WireGuard VPN 테스트 스크립트
# - 단일 클라이언트 연결 테스트용
# - 동글 인터페이스(enp0s21f0u4) 전용
#====================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 설정
DONGLE_INTERFACE="enp0s21f0u4"
VPN_INTERFACE="wg_dongle"
VPN_PORT="55556"
VPN_SUBNET="10.9.0"
CLIENT_IP="${VPN_SUBNET}.10"

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   동글 VPN 테스트 시작${NC}"
echo -e "${GREEN}=====================================${NC}"
echo

# 1. 동글 인터페이스 확인
echo -e "${YELLOW}[1/5] 동글 인터페이스 확인...${NC}"
if ! ip addr show $DONGLE_INTERFACE &>/dev/null; then
    echo -e "${RED}❌ 동글 인터페이스를 찾을 수 없습니다: $DONGLE_INTERFACE${NC}"
    exit 1
fi

DONGLE_IP=$(ip -4 addr show $DONGLE_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo -e "${GREEN}✓ 동글 IP: $DONGLE_IP${NC}"

# 동글 공인 IP 확인 (라우팅 테이블 이용)
echo -e "${YELLOW}동글 공인 IP 확인 중...${NC}"
DONGLE_PUBLIC_IP=$(ip route get 8.8.8.8 oif $DONGLE_INTERFACE | grep -oP 'src \K[\d.]+' 2>/dev/null || echo "")

if [ -z "$DONGLE_PUBLIC_IP" ]; then
    # NAT 뒤에 있는 경우
    echo -e "${YELLOW}⚠ 동글이 NAT 뒤에 있습니다. 직접 연결 불가능할 수 있습니다.${NC}"
    DONGLE_PUBLIC_IP=$DONGLE_IP
fi

echo -e "${GREEN}✓ 동글 공인 IP: $DONGLE_PUBLIC_IP${NC}"
echo

# 2. 기존 설정 정리
echo -e "${YELLOW}[2/5] 기존 VPN 설정 정리...${NC}"
if [ -f /etc/wireguard/${VPN_INTERFACE}.conf ]; then
    wg-quick down $VPN_INTERFACE 2>/dev/null || true
    rm -f /etc/wireguard/${VPN_INTERFACE}.conf
fi
rm -f /etc/wireguard/test_*.key /etc/wireguard/test_*.pub
echo -e "${GREEN}✓ 정리 완료${NC}"
echo

# 3. WireGuard 키 생성
echo -e "${YELLOW}[3/5] WireGuard 키 생성...${NC}"
cd /etc/wireguard

# 서버 키
wg genkey | tee test_server.key | wg pubkey > test_server.pub
SERVER_PRIVATE_KEY=$(cat test_server.key)
SERVER_PUBLIC_KEY=$(cat test_server.pub)
echo -e "${GREEN}✓ 서버 키 생성 완료${NC}"

# 클라이언트 키
wg genkey | tee test_client.key | wg pubkey > test_client.pub
CLIENT_PRIVATE_KEY=$(cat test_client.key)
CLIENT_PUBLIC_KEY=$(cat test_client.pub)
echo -e "${GREEN}✓ 클라이언트 키 생성 완료${NC}"
echo

# 4. WireGuard 서버 설정
echo -e "${YELLOW}[4/5] WireGuard 서버 설정...${NC}"

cat > /etc/wireguard/${VPN_INTERFACE}.conf << EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${VPN_SUBNET}.1/24
ListenPort = ${VPN_PORT}
SaveConfig = false

# 동글 인터페이스로 나가도록 라우팅
PostUp = iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}.0/24 -o ${DONGLE_INTERFACE} -j MASQUERADE
PostUp = iptables -A FORWARD -i ${VPN_INTERFACE} -o ${DONGLE_INTERFACE} -j ACCEPT
PostUp = iptables -A FORWARD -i ${DONGLE_INTERFACE} -o ${VPN_INTERFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}.0/24 -o ${DONGLE_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${VPN_INTERFACE} -o ${DONGLE_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -i ${DONGLE_INTERFACE} -o ${VPN_INTERFACE} -j ACCEPT

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

echo -e "${GREEN}✓ 서버 설정 완료${NC}"
echo

# 5. 방화벽 설정
echo -e "${YELLOW}[5/5] 방화벽 설정...${NC}"
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=${VPN_PORT}/udp 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    echo -e "${GREEN}✓ firewalld 포트 ${VPN_PORT}/udp 추가${NC}"
elif command -v ufw &> /dev/null; then
    ufw allow ${VPN_PORT}/udp 2>/dev/null || true
    echo -e "${GREEN}✓ ufw 포트 ${VPN_PORT}/udp 추가${NC}"
fi
echo

# 6. WireGuard 시작
echo -e "${YELLOW}WireGuard 시작...${NC}"
wg-quick up ${VPN_INTERFACE}
echo -e "${GREEN}✓ WireGuard 시작 완료${NC}"
echo

# 7. 클라이언트 설정 파일 생성
CLIENT_CONF="/home/vpn/test_client.conf"
cat > $CLIENT_CONF << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${DONGLE_PUBLIC_IP}:${VPN_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   동글 VPN 테스트 설정 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}서버 정보:${NC}"
echo -e "  동글 공인 IP: ${GREEN}${DONGLE_PUBLIC_IP}${NC}"
echo -e "  VPN 포트: ${GREEN}${VPN_PORT}${NC}"
echo -e "  VPN 인터페이스: ${GREEN}${VPN_INTERFACE}${NC}"
echo -e "  클라이언트 IP: ${GREEN}${CLIENT_IP}${NC}"
echo
echo -e "${YELLOW}클라이언트 설정:${NC}"
echo -e "${GREEN}${CLIENT_CONF}${NC}"
echo
echo -e "${YELLOW}아래 내용을 외부 클라이언트에 복사하세요:${NC}"
echo -e "${GREEN}=====================================${NC}"
cat $CLIENT_CONF
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}VPN 상태 확인:${NC}"
wg show ${VPN_INTERFACE}
echo
echo -e "${YELLOW}테스트 종료 시:${NC}"
echo -e "  wg-quick down ${VPN_INTERFACE}"
echo
