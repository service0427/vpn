# VPN IP 롤링 시스템

WireGuard VPN을 사용한 IP 롤링 시스템 - HTTP/2, HTTP/3 완벽 지원

## 🎯 핵심 기능

- ✅ **HTTP/3 지원**: 네이버 등 QUIC 프로토콜 완벽 지원
- ✅ **IP 롤링**: 여러 VPS IP를 자유롭게 전환
- ✅ **프록시 불필요**: curl-cffi, playwright 코드 수정 없이 사용
- ✅ **SSH 보호**: VPN 전환 시에도 SSH 연결 유지
- ✅ **자동화**: 한 줄 명령으로 VPN 전환

## 📋 요구사항

- **VPS 서버**: Ubuntu 22.04 / Rocky Linux 9 (VPN 서버용)
- **크롤링 서버**: Ubuntu 22.04 / Rocky Linux 9 (VPN 클라이언트용)
- **Root 권한**

## 🚀 빠른 시작

### 1단계: VPS에 VPN 서버 설치

각 VPS에서 실행:

```bash
git clone https://github.com/service0427/vpn.git
cd vpn/server
chmod +x setup-vpn-server.sh
sudo ./setup-vpn-server.sh
```

출력된 **클라이언트 설정 파일**을 복사하세요!

### 2단계: 크롤링 서버에 VPN 클라이언트 설치

```bash
git clone https://github.com/service0427/vpn.git
cd vpn/client
chmod +x *.sh

# 초기 설치
sudo ./setup-vpn-client.sh

# VPN 추가 (Interactive - 복사-붙여넣기)
sudo ./add-vpn-interactive.sh
# 인터페이스명 입력: wg0
# 방법 선택: 1 (복사-붙여넣기)
# 서버 설정 붙여넣기 후 Ctrl+D

# 또는 파일로 추가
sudo ./add-vpn.sh wg0 ~/vps1-client.conf

# SSH 보호
sudo ./protect-ssh.sh
```

### 3단계: VPN 사용

```bash
# VPN1 활성화 (VPS1 IP 사용)
sudo ./switch-vpn.sh 1

# IP 확인
curl ifconfig.me

# VPN2로 전환 (VPS2 IP 사용)
sudo ./switch-vpn.sh 2

# IP 확인
curl ifconfig.me

# VPN 비활성화 (메인 IP 사용)
sudo ./switch-vpn.sh 0
```

## 📚 스크립트 설명

### 서버용 (VPS)

| 스크립트 | 설명 |
|---------|------|
| `setup-vpn-server.sh` | VPN 서버 자동 설치 및 설정 |

### 클라이언트용 (크롤링 서버)

| 스크립트 | 설명 |
|---------|------|
| `setup-vpn-client.sh` | 초기 설치 (WireGuard 등) |
| `add-vpn.sh` | 새로운 VPN 연결 추가 |
| `switch-vpn.sh` | VPN 전환 (IP 롤링) |
| `protect-ssh.sh` | SSH 보호 설정 |
| `test-vpn.sh` | VPN 상태 종합 테스트 |

## 💻 사용 예제

### Python (curl-cffi)

```python
from curl_cffi import requests

# 프록시 설정 없음! VPN이 자동으로 적용됨
response = requests.get("https://www.naver.com")
print(response.status_code)

# VPN 전환 (터미널에서)
# sudo ./switch-vpn.sh 2

# 이제 다른 IP로 요청됨 (코드 수정 없음!)
response = requests.get("https://www.naver.com")
```

### Playwright

```python
from playwright.async_api import async_playwright

async with async_playwright() as p:
    browser = await p.chromium.launch()
    page = await browser.new_page()

    # 프록시 설정 없음! VPN IP로 자동 연결
    await page.goto("https://www.coupang.com")
```

## 🛡️ SSH 보호

`protect-ssh.sh`를 실행하면:
- VPN 활성화 중에도 SSH 연결 유지
- 새로운 SSH 연결도 메인 IP로 연결
- Policy routing으로 구현

```bash
sudo ./protect-ssh.sh

# VPN 전환해도 SSH 끊기지 않음!
sudo ./switch-vpn.sh 1
```

## 🔍 모니터링

```bash
# VPN 상태 종합 확인
sudo ./test-vpn.sh

# 수동 확인
sudo wg show              # WireGuard 상태
ip route show | grep default  # 라우팅 테이블
curl ifconfig.me          # 현재 외부 IP
```

## 📊 동작 원리

### Routing Metric

```bash
# 기본 상태 (모든 VPN 비활성)
default via ens160 metric 100  ← SSH, 일반 트래픽
default via wg0 metric 900     (비활성)
default via wg1 metric 900     (비활성)

# VPN1 활성화
default via ens160 metric 100  ← SSH만
default via wg0 metric 50      ← 웹 트래픽 (활성!)
default via wg1 metric 900     (비활성)
```

**Metric이 낮을수록 우선순위 높음** → OS가 자동으로 선택!

### Policy Routing (SSH 보호)

```bash
# SSH 패킷은 항상 메인 인터페이스 사용
ip rule add from <서버IP> table main priority 100

# 결과:
# - SSH: 메인 IP 사용 (VPN 영향 안 받음)
# - 웹 트래픽: Metric 낮은 인터페이스 사용 (VPN)
```

## ❓ FAQ

**Q: curl-cffi에서 프록시 설정이 정말 필요 없나요?**
A: 네! VPN은 네트워크 레벨에서 작동하므로 애플리케이션 수정 불필요합니다.

**Q: HTTP/3 (QUIC)가 정말 작동하나요?**
A: 네! VPN은 투명한 터널이므로 모든 프로토콜이 그대로 전달됩니다.

**Q: VPN 전환 시 SSH가 끊기지 않나요?**
A: `protect-ssh.sh`를 실행하면 끊기지 않습니다. Policy routing으로 보호됩니다.

**Q: 여러 VPN을 동시에 사용할 수 있나요?**
A: 아니요. 한 번에 하나의 VPN만 활성화해야 합니다 (metric 기반 라우팅).

## 🔧 문제 해결

### VPN 연결 안 됨

```bash
# 방화벽 확인 (VPS 서버에서)
sudo firewall-cmd --list-all

# 포트 열기
sudo firewall-cmd --permanent --add-port=51820/udp
sudo firewall-cmd --reload

# VPN 재시작
sudo systemctl restart wg-quick@wg0
```

### IP가 변경되지 않음

```bash
# 라우팅 확인
ip route show | grep default

# Metric 확인 - 50이 없으면 문제
sudo ./switch-vpn.sh 1
ip route show | grep "metric 50"
```

### 인터넷 안 됨 (VPN 활성화 후)

```bash
# VPS 서버에서 IP 포워딩 확인
sysctl net.ipv4.ip_forward
# 0이면 문제

# 활성화
sudo sysctl -w net.ipv4.ip_forward=1
```

## 📖 상세 문서

- [WHY-VPN.md](docs/WHY-VPN.md) - VPN이 필요한 이유
- [LOCAL-TEST-GUIDE.md](docs/LOCAL-TEST-GUIDE.md) - VMware로 로컬 테스트
- [REQUIREMENTS.md](docs/REQUIREMENTS.md) - 전체 요구사항 분석

## 🤝 기여

이슈 및 PR 환영합니다!

## 📝 라이선스

MIT License

## 🎉 시작하기

```bash
# VPS1 설정
ssh vps1
git clone https://github.com/service0427/vpn.git
cd vpn/server && sudo ./setup-vpn-server.sh

# VPS2 설정
ssh vps2
git clone https://github.com/service0427/vpn.git
cd vpn/server && sudo ./setup-vpn-server.sh

# 크롤링 서버 설정
git clone https://github.com/service0427/vpn.git
cd vpn/client
sudo ./setup-vpn-client.sh
sudo ./add-vpn.sh wg0 ~/vps1.conf
sudo ./add-vpn.sh wg1 ~/vps2.conf
sudo ./protect-ssh.sh

# 테스트!
sudo ./switch-vpn.sh 1 && curl ifconfig.me
```

**Happy IP Rotating! 🚀**
