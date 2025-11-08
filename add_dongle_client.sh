#!/bin/bash

#====================================
# 동글 VPN 클라이언트 추가 스크립트
#====================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VPN_INTERFACE="wg1"
VPN_SUBNET="10.0.1"
SERVER_IP=$(curl -s ifconfig.me)

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   동글 VPN 클라이언트 추가${NC}"
echo -e "${GREEN}=====================================${NC}"
echo

# wg1 설정 확인
if [ ! -f /etc/wireguard/${VPN_INTERFACE}.conf ]; then
    echo -e "${RED}❌ wg1이 설정되어 있지 않습니다${NC}"
    echo -e "${YELLOW}먼저 /home/vpn/install_dongle_vpn.sh를 실행하세요${NC}"
    exit 1
fi

# 서버 공개키 가져오기
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/${VPN_INTERFACE}_server.pub 2>/dev/null)
if [ -z "$SERVER_PUBLIC_KEY" ]; then
    echo -e "${RED}서버 공개키를 찾을 수 없습니다${NC}"
    exit 1
fi

# 포트 가져오기
VPN_PORT=$(grep "ListenPort" /etc/wireguard/${VPN_INTERFACE}.conf | awk '{print $3}')

# 사용 중인 IP 확인
echo -e "${YELLOW}현재 할당된 IP 확인 중...${NC}"
USED_IPS=$(grep "AllowedIPs" /etc/wireguard/${VPN_INTERFACE}.conf | awk '{print $3}' | cut -d'/' -f1 | cut -d'.' -f4 | sort -n)

# 다음 사용 가능한 IP 찾기
NEXT_IP=2
for ip in $USED_IPS; do
    if [ $ip -eq $NEXT_IP ]; then
        NEXT_IP=$((NEXT_IP + 1))
    fi
done

if [ $NEXT_IP -gt 254 ]; then
    echo -e "${RED}❌ 더 이상 할당 가능한 IP가 없습니다${NC}"
    exit 1
fi

CLIENT_IP="${VPN_SUBNET}.${NEXT_IP}"

echo -e "${GREEN}새 클라이언트 IP: ${CLIENT_IP}${NC}"
echo

# 클라이언트 이름 입력
read -p "클라이언트 이름 (예: user1): " CLIENT_NAME
if [ -z "$CLIENT_NAME" ]; then
    CLIENT_NAME="client_${NEXT_IP}"
fi

# 클라이언트 키 생성
echo -e "${GREEN}클라이언트 키 생성 중...${NC}"
CLIENT_PRIVATE=$(wg genkey)
CLIENT_PUBLIC=$(echo ${CLIENT_PRIVATE} | wg pubkey)

# 서버 설정에 Peer 추가
echo -e "${GREEN}서버에 클라이언트 추가 중...${NC}"

# 임시 파일에 새 peer 정보 저장
cat >> /tmp/new_peer_${VPN_INTERFACE}.conf << EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32
EOF

# wg1 중지
wg-quick down ${VPN_INTERFACE} 2>/dev/null

# 설정 파일에 추가
cat /tmp/new_peer_${VPN_INTERFACE}.conf >> /etc/wireguard/${VPN_INTERFACE}.conf
rm /tmp/new_peer_${VPN_INTERFACE}.conf

# wg1 시작
wg-quick up ${VPN_INTERFACE}

# 클라이언트 설정 파일 생성
CLIENT_CONF_DIR="/etc/wireguard/dongle_clients"
mkdir -p ${CLIENT_CONF_DIR}

CLIENT_CONF_FILE="${CLIENT_CONF_DIR}/${CLIENT_NAME}.conf"

cat > ${CLIENT_CONF_FILE} << EOF
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

# QR 코드 생성 (옵션)
if command -v qrencode &> /dev/null; then
    echo -e "${GREEN}QR 코드 생성 중...${NC}"
    qrencode -t ansiutf8 < ${CLIENT_CONF_FILE}
fi

echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   클라이언트 추가 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}클라이언트 정보:${NC}"
echo -e "  이름: ${CLIENT_NAME}"
echo -e "  IP: ${CLIENT_IP}"
echo -e "  공개키: ${CLIENT_PUBLIC}"
echo
echo -e "${YELLOW}설정 파일:${NC}"
echo -e "  ${CLIENT_CONF_FILE}"
echo
echo -e "${YELLOW}클라이언트 설정 내용:${NC}"
echo "----------------------------------------"
cat ${CLIENT_CONF_FILE}
echo "----------------------------------------"
echo
echo -e "${GREEN}이 설정을 클라이언트의 WireGuard에 추가하세요${NC}"
echo
echo -e "${YELLOW}중요: 이 VPN을 통한 모든 트래픽은 동글을 통해 라우팅됩니다${NC}"