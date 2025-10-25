# VPN Client (IP Rotation)

여러 VPN 서버를 동시에 사용하여 IP를 자유롭게 전환하는 클라이언트입니다.

## 🎯 주요 기능

- ✅ **여러 VPN 동시 사용**: vpn0, vpn1, vpn2... 각각 다른 IP
- ✅ **UID 기반 라우팅**: 사용자별로 다른 VPN 사용
- ✅ **API 기반 동기화**: SSH 키 설정 불필요
- ✅ **간편한 실행**: `vpn 0 curl ifconfig.me`
- ✅ **HTTP/3 지원**: QUIC/UDP 프로토콜 완벽 지원

## 📋 요구사항

- **OS**: Rocky Linux, CentOS, RHEL, Ubuntu, Debian
- **권한**: root
- **설치 도구**: curl, jq, wireguard-tools

## 🚀 빠른 시작

### 1. VPN 목록 동기화

API 서버에서 등록된 모든 VPN을 자동으로 다운로드하여 설정합니다.

```bash
cd /home/vpn/client
./sync.sh
```

**자동으로 수행되는 작업:**
1. ✅ API 서버에서 VPN 목록 조회
2. ✅ 각 VPN 설정 파일 다운로드
3. ✅ WireGuard 인터페이스 생성 (wg0, wg1, ...)
4. ✅ VPN 사용자 생성 (vpn0, vpn1, ...)
5. ✅ UID 기반 라우팅 설정
6. ✅ rp_filter 설정 (Reverse Path Filtering)

### 2. VPN 사용

#### 방법 1: 직접 실행 (CLI)

```bash
# VPN 0번 사용
vpn 0 curl ifconfig.me

# VPN 1번 사용
vpn 1 python crawl.py

# VPN 0번으로 웹사이트 접속
vpn 0 curl https://naver.com
```

#### 방법 2: sudo -u 사용

```bash
sudo -u vpn0 curl ifconfig.me
sudo -u vpn1 python crawl.py
```

#### 방법 3: 대화형 모드

```bash
vpn
```

메뉴에서 VPN을 선택하고 명령어를 입력합니다.

### 3. 동시에 여러 VPN 사용

```bash
# 동시에 다른 IP로 요청
sudo -u vpn0 curl ifconfig.me &
sudo -u vpn1 curl ifconfig.me &
sudo -u vpn2 curl ifconfig.me &
wait
```

## 📂 파일 구조

```
/home/vpn/client/
├── sync.sh              # VPN 동기화 (API 기반)
├── setup-vpnusers.sh    # VPN 사용자 생성 (자동 실행됨)
└── vpn                  # VPN 실행 wrapper

/etc/wireguard/
├── wg0.conf             # VPN 서버 1 설정
├── wg1.conf             # VPN 서버 2 설정
└── wg2.conf             # VPN 서버 3 설정...

/etc/sysctl.d/
└── 99-vpn-routing.conf  # rp_filter 설정

/etc/systemd/system/
└── vpn-routing.service  # 재부팅 시 자동 복구
```

## 🔧 VPN 관리

### VPN 목록 확인

```bash
# WireGuard 인터페이스
wg show interfaces

# VPN 사용자
cat /etc/passwd | grep vpn

# 라우팅 규칙
ip rule list

# 라우팅 테이블
ip route show table 100
ip route show table 101
```

### VPN 연결 상태 확인

```bash
# 모든 VPN 상태
wg show

# 특정 VPN 상태
wg show wg0

# Handshake 확인 (최근 연결 시각)
wg show wg0 latest-handshakes
```

### VPN 재시작

```bash
# 특정 VPN 재시작
systemctl restart wg-quick@wg0

# 모든 VPN 재시작
for i in $(wg show interfaces); do
  systemctl restart wg-quick@$i
done

# 라우팅 재설정
./setup-vpnusers.sh
```

### VPN 추가/제거

```bash
# VPN 추가 (API 서버에 등록된 경우)
./sync.sh

# 특정 VPN 제거
systemctl stop wg-quick@wg0
systemctl disable wg-quick@wg0
rm /etc/wireguard/wg0.conf
userdel -r vpn0
```

## 🛠️ VPN Wrapper 사용법

### 기본 사용법

```bash
vpn <VPN번호> <명령어>
```

### 예시

```bash
# IP 확인
vpn 0 curl ifconfig.me
vpn 1 curl ifconfig.me

# 웹 크롤링
vpn 0 python crawl.py
vpn 1 node scraper.js

# curl-cffi 사용
vpn 0 python -c "from curl_cffi import requests; print(requests.get('https://naver.com').text)"

# 여러 명령어 연속 실행
vpn 0 bash -c 'curl ifconfig.me && curl https://naver.com'
```

### 대화형 모드

```bash
# 명령어 없이 실행
vpn

# 출력 예시:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  사용 가능한 VPN 목록
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [1] vpn0 → wg0 (IP: 10.8.0.2)
  [2] vpn1 → wg1 (IP: 10.8.0.2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VPN 번호를 선택하세요: 1

실행할 명령어를 입력하세요: curl ifconfig.me
```

## 🔍 작동 원리

### UID 기반 라우팅

각 VPN 사용자(vpn0, vpn1)는 고유한 UID를 가지며, 리눅스 Policy Routing으로 트래픽을 분리합니다.

```bash
# vpn0 사용자 (UID: 1000) → wg0 (table 100)
ip rule add uidrange 1000-1000 table 100
ip route add default via 10.8.0.1 dev wg0 table 100

# vpn1 사용자 (UID: 1001) → wg1 (table 101)
ip rule add uidrange 1001-1001 table 101
ip route add default via 10.8.0.1 dev wg1 table 101
```

### rp_filter 설정

UID 기반 라우팅이 작동하려면 Reverse Path Filtering을 loose mode로 설정해야 합니다.

```bash
# /etc/sysctl.d/99-vpn-routing.conf
net.ipv4.conf.all.rp_filter=2
net.ipv4.conf.default.rp_filter=2
```

이 설정은 `sync.sh` 실행 시 자동으로 적용됩니다.

## 📊 테스트

### IP 확인

```bash
# 일반 IP
curl ifconfig.me

# VPN 0 (첫 번째 VPN 서버 IP)
vpn 0 curl ifconfig.me

# VPN 1 (두 번째 VPN 서버 IP)
vpn 1 curl ifconfig.me
```

### 연결 테스트

```bash
# VPN 게이트웨이 ping
ping -c 3 10.8.0.1

# VPN을 통한 외부 ping
vpn 0 ping -c 3 8.8.8.8

# HTTP/3 테스트 (curl-cffi)
vpn 0 python -c "from curl_cffi import requests; r = requests.get('https://cloudflare.com'); print(r.status_code)"
```

## 🔍 트러블슈팅

### 1. VPN 연결은 되지만 인터넷 안됨

```bash
# rp_filter 확인
sysctl net.ipv4.conf.all.rp_filter

# 2가 아니면 수정
sudo sysctl -w net.ipv4.conf.all.rp_filter=2
sudo sysctl -w net.ipv4.conf.default.rp_filter=2

# 테스트
vpn 0 ping -c 3 8.8.8.8
```

### 2. 특정 VPN만 안됨

```bash
# VPN 서버 상태 확인
wg show wg0

# Handshake 시간 확인 (최근이어야 함)
# latest handshake: 1 minute, 30 seconds ago

# 재시작
systemctl restart wg-quick@wg0

# 서버 로그 확인 (VPN 서버에서)
ssh root@119.193.40.11 "journalctl -u wg-quick@wg0 -n 50"
```

### 3. 라우팅 규칙 꼬임

```bash
# 라우팅 초기화
./setup-vpnusers.sh

# 또는 수동 제거
ip rule list | grep "lookup 10" | while read line; do
    PRIORITY=$(echo "$line" | awk '{print $1}' | tr -d ':')
    ip rule del priority $PRIORITY 2>/dev/null || true
done
```

### 4. VPN 동기화 실패

```bash
# API 서버 확인
curl http://112.161.221.82/health

# VPN 목록 확인
curl http://112.161.221.82/api/vpn/list | jq

# 수동 다운로드
VPN_NAME="vpn-119-193-40-11"
curl http://112.161.221.82/api/vpn/$VPN_NAME/config
```

## 🔄 완전 리셋

모든 VPN 설정을 제거하고 처음부터 다시 설정합니다.

```bash
# 1. 모든 VPN 제거
for iface in $(wg show interfaces 2>/dev/null); do
    systemctl stop wg-quick@${iface}
    systemctl disable wg-quick@${iface}
    rm -f /etc/wireguard/${iface}.conf
done

# 2. VPN 사용자 제거
for user in vpn0 vpn1 vpn2 vpn3 vpn4 vpn5; do
    id "$user" &>/dev/null && userdel -r "$user" 2>/dev/null || true
done

# 3. 라우팅 규칙 제거
ip rule list | grep "lookup 10" | while read line; do
    PRIORITY=$(echo "$line" | awk '{print $1}' | tr -d ':')
    ip rule del priority $PRIORITY 2>/dev/null || true
done

# 4. 시스템 설정 제거
rm -f /etc/sysctl.d/99-vpn-routing.conf
systemctl stop vpn-routing.service 2>/dev/null || true
systemctl disable vpn-routing.service 2>/dev/null || true
rm -f /etc/systemd/system/vpn-routing.service
systemctl daemon-reload

# 5. 새로 설정
./sync.sh
```

## 🌐 API 정보

### API 서버
- **주소**: `112.161.221.82`
- **DB**: `220.121.120.83`

### API 엔드포인트

```bash
# 헬스 체크
curl http://112.161.221.82/health

# VPN 목록 조회
curl http://112.161.221.82/api/vpn/list

# VPN 설정 다운로드
curl http://112.161.221.82/api/vpn/{name}/config
```

## 📌 주의사항

1. **root 권한 필수**: 모든 스크립트는 root로 실행해야 합니다
2. **재부팅 후 자동 복구**: `vpn-routing.service`가 자동으로 라우팅을 복구합니다
3. **DNS 설정**: Rocky Linux 10 호환성을 위해 DNS는 제거됩니다
4. **동시 사용**: 여러 VPN을 동시에 사용할 수 있습니다

## 🔗 관련 링크

- [서버 설치 가이드](../server/README.md)
- [WireGuard 공식 문서](https://www.wireguard.com/)
