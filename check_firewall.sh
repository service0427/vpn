#!/bin/bash

# 방화벽 상태 확인 스크립트

echo "======================================"
echo "   방화벽 상태 확인"
echo "======================================"
echo

# 1. 기본 정보
echo "📋 기본 정보:"
firewall-cmd --state
firewall-cmd --get-default-zone
echo

# 2. 열린 서비스
echo "🔓 허용된 서비스:"
firewall-cmd --list-services
echo

# 3. 열린 포트
echo "🔌 열린 포트:"
firewall-cmd --list-ports
echo

# 4. SSH 포트 확인
echo "🔐 SSH 상태:"
if firewall-cmd --list-services | grep -q ssh; then
    echo "✅ SSH 서비스 활성화됨"
else
    echo "⚠️  SSH 서비스가 방화벽에 없습니다!"
fi

# SSH 포트 확인
SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
echo "SSH 포트: $SSH_PORT"
echo

# 5. 중요 포트 체크
echo "🔍 중요 포트 상태:"
CRITICAL_PORTS="22 80 443 3306 55555"
for port in $CRITICAL_PORTS; do
    if firewall-cmd --list-all | grep -E "ports:|services:" | grep -q "$port"; then
        echo "  ✅ 포트 $port 열림"
    else
        echo "  ❌ 포트 $port 닫힘"
    fi
done
echo

# 6. 전체 설정
echo "📊 전체 방화벽 설정:"
firewall-cmd --list-all

echo
echo "======================================"
echo "⚠️  주의사항:"
echo "- SSH(22)는 절대 차단하지 마세요"
echo "- 필요한 포트만 열고 나머지는 기본 정책에 맡기세요"
echo "- 방화벽 변경 후 반드시 SSH 접속 테스트하세요"
echo "======================================
"