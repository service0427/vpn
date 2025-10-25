# VPN IP Rotation System

WireGuard 기반 VPN IP 로테이션 시스템 - 웹 크롤링을 위한 다중 IP 관리

## 📋 목차

- [개요](#개요)
- [시스템 구조](#시스템-구조)
- [왜 VPN인가?](#왜-vpn인가)
- [설치 가이드](#설치-가이드)
- [사용 방법](#사용-방법)
- [문제 해결](#문제-해결)

## 개요

이 시스템은 여러 VPN 서버를 동시에 연결하여 각각 다른 IP로 웹 크롤링을 수행할 수 있게 해줍니다.

### 주요 특징

- ✅ **다중 VPN 동시 사용**: 여러 VPN을 동시에 연결하여 IP 로테이션
- ✅ **UID 기반 라우팅**: 각 사용자(vpn0, vpn1, ...)가 특정 VPN 사용
- ✅ **중앙 관리**: API 서버를 통한 VPN 서버 관리
- ✅ **자동 설정**: 스크립트로 간편한 설치 및 동기화
- ✅ **HTTP/3 지원**: QUIC/UDP 프로토콜 완벽 지원
- ✅ **대화형 인터페이스**: 쉬운 VPN 선택 메뉴

## 시스템 구조

```
┌─────────────────────────────────────────────────────────┐
│                    클라이언트 서버                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  vpn0    │  │  vpn1    │  │  vpn2    │              │
│  │ (UID기반)│  │ (UID기반)│  │ (UID기반)│              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │             │             │                     │
│       ▼             ▼             ▼                     │
│  ┌────────┐   ┌────────┐   ┌────────┐                 │
│  │  wg0   │   │  wg1   │   │  wg2   │                 │
│  └────┬───┘   └────┬───┘   └────┬───┘                 │
└───────┼────────────┼────────────┼──────────────────────┘
        │            │            │
        │ VPN 터널   │ VPN 터널   │ VPN 터널
        ▼            ▼            ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐
   │ VPN 1   │  │ VPN 2   │  │ VPN 3   │
   │ IP: A   │  │ IP: B   │  │ IP: C   │
   └─────────┘  └─────────┘  └─────────┘

              ┌──────────────────┐
              │  중계 서버        │
              │  - API 서버      │
              │  - VPN 목록 관리 │
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │  DB 서버         │
              │  - MySQL         │
              │  - VPN 정보 저장 │
              └──────────────────┘
```

## 왜 VPN인가?

### SOCKS5/Squid Proxy의 한계

기존 프록시 시스템은 **HTTP/HTTPS만 지원**하여 다음과 같은 문제가 있습니다:

| 프로토콜 | SOCKS5 | Squid | VPN |
|---------|--------|-------|-----|
| HTTP/1.1 | ✅ | ✅ | ✅ |
| HTTP/2 | ⚠️ 제한적 | ⚠️ 제한적 | ✅ |
| HTTP/3 (QUIC) | ❌ | ❌ | ✅ |
| UDP 기반 앱 | ❌ | ❌ | ✅ |

### HTTP/3 (QUIC)의 중요성

- **HTTP/3**는 UDP 기반 프로토콜
- Google, Cloudflare 등 주요 사이트에서 사용 중
- SOCKS5/Squid는 TCP 기반이라 **HTTP/3를 터널링 불가능**
- **VPN만이 완전한 네트워크 투명성 제공**

### VPN의 장점

```
프록시: 애플리케이션 레벨 (HTTP만)
  └─ curl --proxy socks5://... https://site.com

VPN: 네트워크 레벨 (모든 트래픽)
  └─ vpn 0 curl https://site.com  (자동으로 VPN IP 사용)
```

## 설치 가이드

### 1. VPN 서버 설치

VPN 서버로 사용할 서버에서 실행:

```bash
# 저장소 클론
cd /home
git clone https://github.com/service0427/vpn.git vpn-ip-rotation
cd vpn-ip-rotation/server

# 서버 설치 (자동 API 등록)
sudo ./setup.sh
```

**설치 내용**:
- WireGuard 설치
- 서버 키 생성
- 방화벽 설정 (포트 51820 UDP)
- API 서버에 자동 등록

### 2. 클라이언트 설치

크롤링을 실행할 서버에서:

```bash
# 저장소 클론
cd /home
git clone https://github.com/service0427/vpn.git vpn-ip-rotation
cd vpn-ip-rotation/client

# 클라이언트 초기 설치
sudo ./setup.sh

# VPN 자동 동기화 (API에서 목록 가져옴)
sudo ./sync.sh
```

**설치 내용**:
- WireGuard 클라이언트 설치
- API에서 활성 VPN 목록 조회
- 각 VPN 자동 연결
- VPN 전용 사용자 생성 (vpn0, vpn1, vpn2, ...)
- UID 기반 라우팅 설정

### 3. PATH 설정 (선택)

어디서든 `vpn` 명령 사용:

```bash
# vpn 스크립트를 /usr/local/bin으로 복사
sudo cp /home/vpn-ip-rotation/client/vpn /usr/local/bin/
sudo chmod +x /usr/local/bin/vpn

# 이제 어디서든 실행 가능
vpn
```

## 사용 방법

### 대화형 모드 (추천)

```bash
vpn
```

**실행 예시**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  사용 가능한 VPN 목록
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [1] vpn0 → wg0 (IP: 10.8.0.2)
  [2] vpn1 → wg1 (IP: 10.8.1.2)
  [3] vpn2 → wg2 (IP: 10.8.2.2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VPN 번호를 선택하세요: 1

[선택됨] vpn0

실행할 명령어를 입력하세요: curl ifconfig.me
```

### CLI 모드

직접 명령 실행:

```bash
# VPN 0번으로 IP 확인
vpn 0 curl ifconfig.me

# VPN 1번으로 크롤링
vpn 1 python3 crawl.py

# VPN 2번으로 curl
vpn 2 curl https://www.naver.com

# 복잡한 명령도 가능
vpn 0 bash -c "curl ifconfig.me && curl ipinfo.io"
```

### Python 크롤링 예제

```python
# crawl.py
import requests

# VPN IP를 사용하여 크롤링
response = requests.get('https://ifconfig.me')
print(f"현재 IP: {response.text}")

# HTTP/3도 자동 지원
response = requests.get('https://www.google.com')
print(f"Status: {response.status_code}")
```

**실행**:
```bash
# VPN 0번 IP로 크롤링
vpn 0 python3 crawl.py

# VPN 1번 IP로 크롤링
vpn 1 python3 crawl.py
```

### Playwright/Selenium 사용

Playwright나 Selenium도 **프록시 설정 없이** 자동으로 VPN IP 사용:

```python
# playwright_example.py
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()

    # 자동으로 VPN IP 사용됨
    page.goto('https://ifconfig.me')
    print(page.content())

    browser.close()
```

```bash
# VPN 0번으로 브라우저 실행
vpn 0 python3 playwright_example.py
```

## 고급 사용

### VPN 목록 확인

```bash
# 연결된 VPN 인터페이스
wg show interfaces

# 각 VPN 상태
wg show

# VPN 사용자 목록
cat /etc/passwd | grep vpn
```

### SSH 보호

VPN 연결 시 SSH 연결이 끊기지 않도록 보호:

```bash
sudo /home/vpn-ip-rotation/client/protect.sh
```

### VPN 재동기화

새로운 VPN 서버가 추가되면:

```bash
cd /home/vpn-ip-rotation/client
sudo ./sync.sh
```

### 수동으로 VPN 추가

```bash
cd /home/vpn-ip-rotation/client
sudo ./add.sh root@119.193.40.11 wg-kr-seoul-01
```

## 문제 해결

### VPN 연결 실패

```bash
# VPN 상태 확인
sudo systemctl status wg-quick@wg0

# 로그 확인
sudo journalctl -u wg-quick@wg0 -f

# VPN 재시작
sudo systemctl restart wg-quick@wg0
```

### 라우팅 문제

```bash
# 라우팅 테이블 확인
ip route show

# VPN 사용자의 라우팅 규칙 확인
ip rule show

# vpn0 사용자의 실제 IP 확인
sudo -u vpn0 curl ifconfig.me
```

### VPN 사용자가 없음

```bash
# VPN 사용자 재생성
cd /home/vpn-ip-rotation/client
sudo ./setup-vpnusers.sh
```

### API 서버 연결 실패

```bash
# API 서버 상태 확인
curl http://112.161.221.82/health

# VPN 목록 확인
curl http://112.161.221.82/api/vpn/list | jq
```

## 시스템 요구사항

### VPN 서버
- OS: Rocky Linux 9+, Ubuntu 20.04+
- 공인 IP 필수
- 포트: 51820 UDP 오픈

### 클라이언트
- OS: Rocky Linux 9+, Ubuntu 20.04+
- WireGuard 지원
- Root 권한

### 중계 서버
- Node.js 18+
- MySQL 접근 권한

## 아키텍처

### 파일 구조

```
vpn-ip-rotation/
├── server/              # VPN 서버 설치
│   └── setup.sh         # 서버 자동 설치 스크립트
├── client/              # VPN 클라이언트
│   ├── setup.sh         # 클라이언트 초기 설치
│   ├── sync.sh          # API에서 VPN 목록 동기화
│   ├── add.sh           # 개별 VPN 추가
│   ├── setup-vpnusers.sh # VPN 사용자 생성
│   ├── protect.sh       # SSH 보호
│   └── vpn              # VPN 실행 래퍼 (메인)
└── README.md            # 이 파일
```

### UID 기반 라우팅

```bash
# 각 VPN 사용자가 특정 VPN 인터페이스 사용
vpn0 (UID: 1001) → wg0 → VPN Server 1
vpn1 (UID: 1002) → wg1 → VPN Server 2
vpn2 (UID: 1003) → wg2 → VPN Server 3

# 라우팅 규칙 (ip rule)
from all uidrange 1001-1001 lookup 100  # vpn0 → table 100
from all uidrange 1002-1002 lookup 101  # vpn1 → table 101
from all uidrange 1003-1003 lookup 102  # vpn2 → table 102

# 라우팅 테이블
table 100: default via wg0  # VPN 1
table 101: default via wg1  # VPN 2
table 102: default via wg2  # VPN 3
```

### 데이터베이스 스키마

```sql
-- vpn_servers 테이블
CREATE TABLE vpn_servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,           -- vpn-119-193-40-11
    host VARCHAR(100) NOT NULL,                 -- root@119.193.40.11
    public_ip VARCHAR(45) NOT NULL,             -- 119.193.40.11
    interface VARCHAR(20) NOT NULL,             -- wg-vpn-119-193-40-11
    region VARCHAR(10),                         -- KR, US, JP
    port INT DEFAULT 51820,
    status ENUM('active', 'inactive', 'error'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## FAQ

**Q: 여러 VPN을 동시에 사용할 수 있나요?**
A: 네! UID 기반 라우팅으로 각 사용자가 다른 VPN을 사용합니다.

**Q: HTTP/3 (QUIC)가 정말 작동하나요?**
A: 네! VPN은 투명한 터널이므로 모든 프로토콜이 그대로 전달됩니다.

**Q: VPN 전환 시 SSH가 끊기지 않나요?**
A: `protect.sh`를 실행하면 끊기지 않습니다. Policy routing으로 보호됩니다.

**Q: curl-cffi에서 프록시 설정이 필요 없나요?**
A: 네! VPN은 네트워크 레벨에서 작동하므로 애플리케이션 수정 불필요합니다.

## 라이센스

MIT License

## 기여

이슈 및 풀 리퀘스트 환영합니다!

## 시작하기

```bash
# VPN 서버 1 설정
ssh vps1
cd /home && git clone https://github.com/service0427/vpn.git vpn-ip-rotation
cd vpn-ip-rotation/server && sudo ./setup.sh

# VPN 서버 2 설정
ssh vps2
cd /home && git clone https://github.com/service0427/vpn.git vpn-ip-rotation
cd vpn-ip-rotation/server && sudo ./setup.sh

# 크롤링 서버 설정
cd /home && git clone https://github.com/service0427/vpn.git vpn-ip-rotation
cd vpn-ip-rotation/client
sudo ./setup.sh
sudo ./sync.sh  # API에서 자동 동기화!

# 대화형 사용
vpn

# 또는 직접 실행
vpn 0 curl ifconfig.me
vpn 1 python3 crawl.py
```

**Happy IP Rotating! 🚀**
