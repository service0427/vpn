# WireGuard VPN 서버 자동 설치

WireGuard VPN 서버를 원클릭으로 설치하고 10개의 클라이언트 키를 자동 생성합니다.

## 🚀 원클릭 설치

```bash
curl -sL https://github.com/service0427/vpn/raw/main/install.sh | sudo bash
```

이 한 줄로 모든 것이 자동으로 설정됩니다:
- ✅ WireGuard VPN 서버 설치
- ✅ 서버 및 10개 클라이언트 키 생성
- ✅ API 서버에 자동 등록
- ✅ 재부팅 시 자동 재설치 설정 (IP 변경 감지)

## 📋 설치 내용

1. WireGuard 설치 (Rocky/RHEL/Ubuntu 자동 감지)
2. 서버 키 생성
3. 10개 클라이언트 키 생성 (10.8.0.10 ~ 10.8.0.19)
4. 방화벽 자동 설정 (포트 55555/UDP)
5. API 서버 자동 등록 (http://220.121.120.83/vpn_api/)
6. Cron 자동 등록 (재부팅 시 자동 재설치)

## 📁 생성되는 파일

- `/etc/wireguard/wg0.conf` - WireGuard 서버 설정
- `/etc/wireguard/clients/client_*.conf` - 클라이언트 설정 파일 10개
- `/home/vpn/vpn_server_data.json` - API 등록 데이터
- `/home/vpn/*.sh` - 관리 스크립트들

## 🔧 관리 명령어

```bash
# VPN 상태 확인
wg show

# 방화벽 확인
/home/vpn/check_firewall.sh

# VPN 재시작
wg-quick down wg0 && wg-quick up wg0

# VPN 완전 제거
/home/vpn/uninstall_vpn.sh

# Cron 확인
crontab -l
```

## 🔄 재부팅 시 자동 처리

설치 후 서버가 재부팅되면:
1. 네트워크 연결 대기 (ping 체크)
2. VPN 서버 자동 재설치
3. 변경된 IP로 API 자동 재등록
4. 새로운 키 10개 생성 및 등록

**VMware 브릿지 변경 등으로 IP가 바뀌어도 자동으로 처리됩니다!**

## 📊 클라이언트 사용법

### 1. API에서 키 할당받기
```bash
curl http://220.121.120.83/vpn_api/allocate
```

### 2. VPN 연결
```bash
# 받은 설정으로 연결
sudo wg-quick up vpn.conf
```

### 3. 사용 후 키 반납
```bash
curl -X POST http://220.121.120.83/vpn_api/release \
  -H "Content-Type: application/json" \
  -d '{"public_key": "클라이언트공개키"}'
```

## 📝 시스템 정보

- **포트**: 55555/UDP
- **내부 네트워크**: 10.8.0.0/24
- **동시 접속**: 10개
- **지원 OS**: Rocky Linux 9 / RHEL 9 / Ubuntu
- **API 서버**: http://220.121.120.83/vpn_api/

## 🔗 API 엔드포인트

- `GET /allocate` - 사용 가능한 키 할당
- `POST /release` - 키 반납
- `POST /server/register` - 서버 등록
- `POST /keys/register` - 키 일괄 등록
- `GET /release/all?ip=<IP>&delete=true` - 서버 완전 삭제

---

**원클릭 설치로 모든 것이 자동화됩니다!**
