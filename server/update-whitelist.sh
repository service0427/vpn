#!/bin/bash

#######################################
# SOCKS5 화이트리스트 수동 업데이트
# GitHub에서 다운로드하여 JSON으로 변환
#######################################

WHITELIST_URL="https://raw.githubusercontent.com/service0427/dongle/main/config/socks5-whitelist.txt"
OUTPUT_FILE="/home/vpn/server/socks5-whitelist.json"

echo "📥 화이트리스트 다운로드 중..."

# GitHub에서 다운로드
TEMP_FILE=$(mktemp)
if ! curl -s -f "$WHITELIST_URL" -o "$TEMP_FILE"; then
    echo "❌ 다운로드 실패"
    rm -f "$TEMP_FILE"
    exit 1
fi

echo "✅ 다운로드 완료"

# IP 추출 (주석 제거, 빈 줄 제거)
IPS=$(grep -v '^#' "$TEMP_FILE" | grep -v '^$' | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

# JSON 생성
echo "{" > "$OUTPUT_FILE"
echo "  \"allowed_ips\": [" >> "$OUTPUT_FILE"

FIRST=1
while IFS= read -r ip; do
    if [ -n "$ip" ]; then
        if [ $FIRST -eq 1 ]; then
            echo "    \"$ip\"" >> "$OUTPUT_FILE"
            FIRST=0
        else
            echo "    ,\"$ip\"" >> "$OUTPUT_FILE"
        fi
    fi
done <<< "$IPS"

echo "  ]," >> "$OUTPUT_FILE"
echo "  \"updated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" >> "$OUTPUT_FILE"
echo "}" >> "$OUTPUT_FILE"

rm -f "$TEMP_FILE"

# 결과 출력
IP_COUNT=$(echo "$IPS" | grep -c .)
echo ""
echo "✅ 화이트리스트 업데이트 완료"
echo "   파일: $OUTPUT_FILE"
echo "   IP 개수: $IP_COUNT"
echo ""
echo "📋 등록된 IP:"
echo "$IPS" | nl

echo ""
echo "🔄 SOCKS5 서비스 재시작 중..."
systemctl restart socks5-vpn

if systemctl is-active --quiet socks5-vpn; then
    echo "✅ SOCKS5 서비스 재시작 완료"
else
    echo "❌ SOCKS5 서비스 재시작 실패"
    systemctl status socks5-vpn --no-pager
fi
