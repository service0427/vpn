#!/bin/bash

#====================================
# VPN 서버 완전 제거 스크립트
# - WireGuard 제거
# - API에서 서버 정보 삭제
# - 모든 설정 정리
#====================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SERVER_IP=$(curl -s ifconfig.me)

echo -e "${RED}=====================================${NC}"
echo -e "${RED}   VPN 서버 완전 제거${NC}"
echo -e "${RED}=====================================${NC}"
echo
echo -e "${YELLOW}경고: 이 작업은 되돌릴 수 없습니다!${NC}"
echo -e "- WireGuard wg0 인터페이스만 제거 (wg1은 유지)"
echo -e "- API에서 서버 및 키 정보 삭제"
echo -e "- /etc/wireguard/wg0.conf 관련 설정만 삭제"
echo
read -p "정말 계속하시겠습니까? (y/N): " confirm

# 기본값은 N (취소)
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo

# 1. API에서 서버 정보 삭제
echo -e "${YELLOW}[1/4] API에서 서버 정보 삭제 중... (IP: ${SERVER_IP})${NC}"
RESPONSE=$(curl -s "http://220.121.120.83/vpn_api/release/all?ip=${SERVER_IP}&delete=true")
if echo "$RESPONSE" | jq '.success' | grep -q true; then
    KEYS_DELETED=$(echo "$RESPONSE" | jq -r '.deleted.keys_deleted // 0')
    echo -e "${GREEN}✓ API에서 서버 정보 삭제 완료 (IP: ${SERVER_IP}, 삭제된 키: ${KEYS_DELETED}개)${NC}"
else
    echo -e "${RED}⚠ API 삭제 실패 (IP: ${SERVER_IP}, 수동으로 처리 필요)${NC}"
fi

# 2. WireGuard 서비스 중지
echo -e "${YELLOW}[2/4] WireGuard 서비스 중지...${NC}"
systemctl stop wg-quick@wg0 2>/dev/null
systemctl disable wg-quick@wg0 2>/dev/null
wg-quick down wg0 2>/dev/null
echo -e "${GREEN}✓ WireGuard 서비스 중지 완료${NC}"

# 3. 설정 파일 삭제 (wg0 관련만)
echo -e "${YELLOW}[3/4] wg0 설정 파일 삭제 중...${NC}"
rm -f /etc/wireguard/wg0.conf
rm -f /etc/wireguard/server.key /etc/wireguard/server.pub
rm -rf /etc/wireguard/clients/  # wg0의 클라이언트 설정
rm -f /home/vpn/vpn_server_data.json
rm -f /root/vpn_keys.json
echo -e "${GREEN}✓ wg0 설정 파일 삭제 완료${NC}"

# 4. 방화벽 규칙 제거 (VPN 포트만)
echo -e "${YELLOW}[4/4] 방화벽 규칙 제거 중 (VPN 포트만)...${NC}"

# 제거 전 현재 상태 확인
echo "현재 방화벽 상태:"
firewall-cmd --list-all | grep -E "services:|ports:" | head -2

# VPN 포트만 제거 (SSH 등은 유지)
VPN_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' /etc/wireguard/wg0.conf 2>/dev/null || echo "55555")
if firewall-cmd --list-ports | grep -q "${VPN_PORT}/udp"; then
    firewall-cmd --permanent --remove-port=${VPN_PORT}/udp 2>/dev/null
    echo -e "${GREEN}✓ VPN 포트 ${VPN_PORT}/udp 제거 완료${NC}"
else
    echo "VPN 포트가 이미 제거되어 있습니다."
fi

# masquerade는 VPN에 필요하므로 제거 (다른 서비스가 사용 중일 수 있으므로 주의)
# firewall-cmd --permanent --remove-masquerade 2>/dev/null

firewall-cmd --reload 2>/dev/null

echo "업데이트된 방화벽 상태:"
firewall-cmd --list-all | grep -E "services:|ports:" | head -2
echo -e "${GREEN}✓ 방화벽 정리 완료 (SSH 등 필수 포트는 유지)${NC}"

echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   VPN 서버 제거 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}제거된 서버: ${SERVER_IP}:${VPN_PORT}${NC}"
echo
echo -e "${YELLOW}다음 단계:${NC}"
echo -e "1. 서버를 재설치하려면:"
echo -e "   ${GREEN}sudo ./install_vpn_server.sh${NC}"
echo
echo -e "2. WireGuard 패키지도 제거하려면:"
echo -e "   ${GREEN}dnf remove -y wireguard-tools${NC}"
echo