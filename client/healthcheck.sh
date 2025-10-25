#!/bin/bash

#######################################
# VPN 헬스체크 스크립트
# 매분 실행하여 VPN 서버 상태 업데이트
#######################################

API_HOST="112.161.221.82"
DB_HOST="220.121.120.83"
DB_USER="vpnuser"
DB_PASS="vpn1324"
DB_NAME="vpn"

# VPN 목록 조회
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT public_ip, port FROM vpn_servers" 2>/dev/null | while read -r public_ip port; do
    # ping으로 간단히 체크 (1초 타임아웃)
    if ping -c 1 -W 1 "$public_ip" > /dev/null 2>&1; then
        # 정상: active로 업데이트
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "UPDATE vpn_servers SET status = 'active', updated_at = CURRENT_TIMESTAMP WHERE public_ip = '$public_ip'" 2>/dev/null
    else
        # 실패: inactive로 업데이트
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "UPDATE vpn_servers SET status = 'inactive', updated_at = CURRENT_TIMESTAMP WHERE public_ip = '$public_ip'" 2>/dev/null
    fi
done
