#!/bin/bash

#====================================
# VPN 서버 설치 스크립트
# - WireGuard VPN 서버 설치
# - 50개 키 자동 생성
# - 데이터베이스 초기화
#====================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 기본 설정
VPN_INTERFACE="wg0"
VPN_PORT="55555"
VPN_SUBNET="10.8.0"
START_IP=10
END_IP=19
SERVER_IP=$(curl -s ifconfig.me)

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   VPN 서버 자동 설치 스크립트${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}서버 IP: ${SERVER_IP}${NC}"
echo -e "${YELLOW}VPN 포트: ${VPN_PORT}${NC}"
echo -e "${YELLOW}키 생성 범위: ${VPN_SUBNET}.${START_IP} ~ ${VPN_SUBNET}.${END_IP}${NC}"
echo

# 1. 필수 패키지 설치
echo -e "${GREEN}[1/6] 필수 패키지 설치...${NC}"

# OS 감지
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
fi

# OS별 패키지 설치
if [[ "$OS" == "ubuntu" ]]; then
    echo -e "${YELLOW}Ubuntu 감지됨...${NC}"
    apt-get update
    apt-get install -y wireguard-tools iptables ufw curl jq
elif [[ "$OS" == "rocky" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    echo -e "${YELLOW}Rocky/RHEL 감지됨...${NC}"
    # EPEL 리포지토리 활성화 (WireGuard 설치를 위해)
    dnf install -y epel-release 2>/dev/null || true
    dnf config-manager --set-enabled crb 2>/dev/null || true
    dnf install -y wireguard-tools iptables firewalld curl jq
else
    echo -e "${RED}지원되지 않는 OS: $OS${NC}"
    echo -e "${YELLOW}수동으로 WireGuard를 설치하세요${NC}"
    exit 1
fi

# 2. IP 포워딩 활성화
echo -e "${GREEN}[2/6] 커널 설정...${NC}"
cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.core.netdev_max_backlog=5000
net.ipv4.tcp_congestion_control=bbr
net.netfilter.nf_conntrack_max=262144
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null

# 3. 기존 WireGuard 설정 정리 (재설치 시)
if [ -f /etc/wireguard/wg0.conf ]; then
    echo -e "${YELLOW}기존 WireGuard 설정 발견. 정리 중...${NC}"
    wg-quick down wg0 2>/dev/null
    systemctl stop wg-quick@wg0 2>/dev/null
    rm -f /etc/wireguard/wg0.conf
    rm -f /etc/wireguard/server.key /etc/wireguard/server.pub
    rm -rf /etc/wireguard/clients/
    echo -e "${GREEN}✓ 기존 설정 정리 완료${NC}"
fi

# 4. WireGuard 키 생성
echo -e "${GREEN}[4/6] WireGuard 서버 키 생성...${NC}"
mkdir -p /etc/wireguard
cd /etc/wireguard

# 서버 키 생성
wg genkey | tee server.key | wg pubkey > server.pub
SERVER_PRIVATE_KEY=$(cat server.key)
SERVER_PUBLIC_KEY=$(cat server.pub)

# 5. WireGuard 설정 파일 생성
echo -e "${GREEN}[5/6] WireGuard 설정 파일 생성...${NC}"
cat > /etc/wireguard/${VPN_INTERFACE}.conf << EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${VPN_SUBNET}.1/24
ListenPort = ${VPN_PORT}
SaveConfig = false

# NAT 설정
PostUp = iptables -t nat -A POSTROUTING -s ${VPN_SUBNET}.0/24 -j MASQUERADE
PostUp = iptables -A FORWARD -i ${VPN_INTERFACE} -j ACCEPT
PostUp = iptables -A FORWARD -o ${VPN_INTERFACE} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${VPN_SUBNET}.0/24 -j MASQUERADE
PostDown = iptables -D FORWARD -i ${VPN_INTERFACE} -j ACCEPT
PostDown = iptables -D FORWARD -o ${VPN_INTERFACE} -j ACCEPT

EOF

# 6. 10개 클라이언트 키 생성 및 등록
echo -e "${GREEN}[6/7] 클라이언트 키 생성 (${START_IP} ~ ${END_IP})...${NC}"
mkdir -p /etc/wireguard/clients

# SQL 파일 시작
cat > /tmp/vpn_keys.sql << 'SQLHEADER'
-- VPN 키 데이터
-- 생성일: $(date)

INSERT INTO vpn_keys (server_id, internal_ip, private_key, public_key, in_use, created_at) VALUES
SQLHEADER

FIRST=1
for i in $(seq ${START_IP} ${END_IP}); do
    CLIENT_IP="${VPN_SUBNET}.${i}"
    echo -e "  생성 중: ${CLIENT_IP}"

    # 클라이언트 키 생성
    CLIENT_PRIVATE=$(wg genkey)
    CLIENT_PUBLIC=$(echo ${CLIENT_PRIVATE} | wg pubkey)

    # WireGuard에 Peer 추가
    cat >> /etc/wireguard/${VPN_INTERFACE}.conf << EOF

[Peer]
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}/32
EOF

    # SQL 데이터 추가
    if [ $FIRST -eq 1 ]; then
        FIRST=0
    else
        echo "," >> /tmp/vpn_keys.sql
    fi
    echo -n "(@server_id, '${CLIENT_IP}', '${CLIENT_PRIVATE}', '${CLIENT_PUBLIC}', 0, NOW())" >> /tmp/vpn_keys.sql

    # 클라이언트 설정 파일 생성
    cat > /etc/wireguard/clients/client_${i}.conf << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = ${CLIENT_IP}/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_IP}:${VPN_PORT}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
done

echo ";" >> /tmp/vpn_keys.sql

# 7. API 서버 연동용 JSON 생성
echo -e "${GREEN}[7/7] API 연동 데이터 생성...${NC}"

# JSON 파일 생성
cat > /home/vpn/vpn_server_data.json << EOF
{
  "server": {
    "public_ip": "${SERVER_IP}",
    "port": ${VPN_PORT},
    "server_pubkey": "${SERVER_PUBLIC_KEY}",
    "memo": "VPN Server - $(hostname)"
  },
  "keys": [
EOF

# 키 정보를 JSON 배열로 추가
FIRST=1
for i in $(seq ${START_IP} ${END_IP}); do
    if [ -f /etc/wireguard/clients/client_${i}.conf ]; then
        CLIENT_IP="${VPN_SUBNET}.${i}"
        CLIENT_PRIVATE=$(grep "PrivateKey" /etc/wireguard/clients/client_${i}.conf | cut -d'=' -f2 | xargs)
        CLIENT_PUBLIC=$(echo ${CLIENT_PRIVATE} | wg pubkey)

        if [ $FIRST -eq 0 ]; then
            echo "," >> /home/vpn/vpn_server_data.json
        fi
        FIRST=0

        cat >> /home/vpn/vpn_server_data.json << EOF
    {
      "internal_ip": "${CLIENT_IP}",
      "private_key": "${CLIENT_PRIVATE}",
      "public_key": "${CLIENT_PUBLIC}"
    }
EOF
    fi
done

cat >> /home/vpn/vpn_server_data.json << EOF

  ]
}
EOF

# 8. 방화벽 설정 (VPN 포트만 추가)
echo -e "${GREEN}방화벽 설정...${NC}"
echo -e "${YELLOW}주의: VPN 포트(${VPN_PORT}/udp)만 추가합니다. SSH 등 기존 설정은 유지됩니다.${NC}"

if [[ "$OS" == "ubuntu" ]]; then
    # Ubuntu UFW 설정
    ufw --force enable 2>/dev/null || true
    ufw allow ${VPN_PORT}/udp
    ufw allow ssh
    echo -e "${GREEN}✓ UFW 방화벽에 VPN 포트 ${VPN_PORT}/udp 추가 완료${NC}"
    ufw status numbered
else
    # Rocky/RHEL firewalld 설정
    systemctl start firewalld 2>/dev/null || true
    systemctl enable firewalld 2>/dev/null || true

    # 현재 열린 포트 확인
    echo "현재 열린 서비스/포트:"
    firewall-cmd --list-all | grep -E "services:|ports:" | head -2

    # VPN 포트만 추가 (기존 설정 유지)
    firewall-cmd --permanent --add-port=${VPN_PORT}/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload

    echo -e "${GREEN}✓ VPN 포트 ${VPN_PORT}/udp 추가 완료${NC}"
    echo "업데이트된 포트 목록:"
    firewall-cmd --list-ports
fi

# 9. WireGuard 시작
echo -e "${GREEN}WireGuard 시작...${NC}"
wg-quick up ${VPN_INTERFACE}
systemctl enable wg-quick@${VPN_INTERFACE}

# 10. 완료 메시지
echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   VPN 서버 설치 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}서버 정보:${NC}"
echo -e "  IP: ${SERVER_IP}"
echo -e "  Port: ${VPN_PORT}"
echo -e "  Public Key: ${SERVER_PUBLIC_KEY}"
echo -e "  Subnet: ${VPN_SUBNET}.0/24"
echo -e "  클라이언트 수: $((END_IP - START_IP + 1))개"
echo
echo -e "${YELLOW}다음 단계:${NC}"
echo -e "1. 생성된 JSON 파일 확인:"
echo -e "   ${GREEN}/home/vpn/vpn_server_data.json${NC}"
echo
echo -e "2. API 서버에 등록 요청:"
echo -e "   서버 등록: POST http://220.121.120.83/vpn_api/server/register"
echo -e "   키 일괄 등록: POST http://220.121.120.83/vpn_api/keys/bulk"
echo
echo -e "3. VPN 상태 확인:"
echo -e "   wg show"
echo
echo -e "${GREEN}클라이언트 설정 파일:${NC}"
echo -e "   /etc/wireguard/clients/ 디렉토리 참조"
echo
echo -e "${GREEN}=====================================${NC}"

# 상태 확인
wg show

# 임시 파일 정리
rm -f /tmp/vpn_keys.sql

# ========================================
# API에 자동 등록
# ========================================

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   중앙 API에 VPN 서버 등록 중...${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# 기존 서버 확인 및 삭제
echo -e "${YELLOW}기존 서버 정보 확인 중...${NC}"
if curl -s "http://220.121.120.83/vpn_api/status?ip=${SERVER_IP}" | jq '.success' | grep -q true; then
    echo -e "${YELLOW}⚠ 기존 서버 정보가 발견되었습니다. 삭제 중...${NC}"
    curl -s "http://220.121.120.83/vpn_api/release/all?ip=${SERVER_IP}&delete=true" > /dev/null
    echo -e "${GREEN}✓ 기존 서버 정보 삭제 완료${NC}"
    echo
fi

# 원라인 자동 등록
if curl -s http://220.121.120.83/vpn_api/one_line_register.sh | bash; then
    echo ""
    echo -e "${GREEN}✅ VPN 서버 설치 및 API 등록 완료!${NC}"
    echo ""
    echo -e "${YELLOW}사용 가능한 명령어:${NC}"
    echo -e "  # 서버 목록 확인"
    echo -e "  curl http://220.121.120.83/vpn_api/list"
    echo ""
    echo -e "  # 키 할당 테스트"
    echo -e "  curl \"http://220.121.120.83/vpn_api/allocate?ip=${SERVER_IP}\""
else
    echo -e "${YELLOW}⚠️ API 등록 실패. 수동으로 등록하세요:${NC}"
    echo -e "  curl -s http://220.121.120.83/vpn_api/one_line_register.sh | bash"
fi

# ========================================
# Heartbeat 설정
# ========================================

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   Heartbeat 설정 중...${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Heartbeat 스크립트를 crontab에 추가
if ! crontab -l 2>/dev/null | grep -q "vpn_heartbeat.sh"; then
    (crontab -l 2>/dev/null; echo "*/1 * * * * /home/vpn/vpn_heartbeat.sh > /dev/null 2>&1") | crontab -
    echo -e "${GREEN}✓ Heartbeat cron 등록 완료 (1분마다 실행)${NC}"
else
    echo -e "${YELLOW}⚠ Heartbeat cron이 이미 등록되어 있습니다${NC}"
fi

echo -e "${GREEN}✓ VPN 서버가 1분마다 상태를 중앙 API로 전송합니다${NC}"