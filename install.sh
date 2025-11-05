#!/bin/bash

#====================================
# VPN 서버 원라인 설치 스크립트
#====================================

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   VPN 서버 원라인 설치${NC}"
echo -e "${GREEN}=====================================${NC}"
echo

# 임시 디렉토리 생성
TEMP_DIR="/tmp/vpn_install_$$"
mkdir -p $TEMP_DIR
cd $TEMP_DIR

echo -e "${YELLOW}설치 스크립트 다운로드 중...${NC}"

# GitHub에서 스크립트 다운로드
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/install_vpn_server.sh -o install_vpn_server.sh
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/uninstall_vpn.sh -o uninstall_vpn.sh
curl -sL https://raw.githubusercontent.com/service0427/vpn/main/check_firewall.sh -o check_firewall.sh

# 실행 권한 부여
chmod +x *.sh

# /home/vpn 디렉토리 생성
mkdir -p /home/vpn

# 스크립트 복사
cp *.sh /home/vpn/
cd /home/vpn

echo -e "${GREEN}설치 시작...${NC}"
echo

# 설치 실행
./install_vpn_server.sh

# 임시 디렉토리 정리
rm -rf $TEMP_DIR

echo
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}   설치 완료!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo
echo -e "${YELLOW}유용한 명령어:${NC}"
echo -e "  VPN 상태 확인: ${GREEN}wg show${NC}"
echo -e "  방화벽 확인: ${GREEN}/home/vpn/check_firewall.sh${NC}"
echo -e "  VPN 재설치: ${GREEN}/home/vpn/install_vpn_server.sh${NC}"
echo -e "  VPN 제거: ${GREEN}/home/vpn/uninstall_vpn.sh${NC}"