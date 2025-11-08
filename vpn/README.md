# VPN 서버 원클릭 설치

WireGuard VPN 서버를 설치하고 10개의 클라이언트 키를 자동 생성하는 스크립트

## 🚀 설치

```bash
sudo ./install_vpn_server.sh
```

## 📋 설치 과정

1. WireGuard 설치
2. 서버 키 생성
3. 10개 클라이언트 키 생성 (10.8.0.10 ~ 10.8.0.19)
4. 방화벽 설정
5. JSON 데이터 파일 생성 (`vpn_server_data.json`)
6. **자동으로 API 서버에 등록** ✨

## 📁 생성되는 파일

- `/etc/wireguard/wg0.conf` - WireGuard 서버 설정
- `/etc/wireguard/clients/client_10.conf ~ client_19.conf` - 클라이언트 설정 파일
- `/home/vpn/vpn_server_data.json` - API 서버 등록용 JSON 데이터

## 🔗 API 서버 연동 (자동)

설치 시 자동으로 API 서버에 등록됩니다!

### 수동 등록 (필요 시)

```
POST http://220.121.120.83/vpn_api/server/register
Content-Type: application/json

{
  "public_ip": "서버IP",
  "port": 55555,
  "server_pubkey": "서버공개키",
  "memo": "VPN Server"
}
```

```
POST http://220.121.120.83/vpn_api/keys/register
Content-Type: application/json

{
  "server_ip": "서버IP",
  "server_port": 55555,
  "keys": [
    {
      "internal_ip": "10.8.0.10",
      "private_key": "...",
      "public_key": "..."
    },
    ...
  ]
}
```

## 📊 사용법

### 클라이언트 VPN 연결

1. API에서 키 할당받기:
```bash
curl http://220.121.120.83/vpn_api/allocate
```

2. 받은 설정으로 VPN 연결:
```bash
# 설정 파일 저장 후
sudo wg-quick up vpn.conf
```

3. 사용 후 키 반납:
```bash
curl -X POST http://220.121.120.83/vpn_api/release \
  -H "Content-Type: application/json" \
  -d '{"public_key": "클라이언트공개키"}'
```

## 🔧 관리 명령어

```bash
# VPN 상태 확인
wg show

# WireGuard 재시작
wg-quick down wg0 && wg-quick up wg0

# 로그 확인
journalctl -u wg-quick@wg0 -f

# VPN 서버 완전 제거
sudo ./uninstall_vpn.sh

# API에서 서버 정보만 삭제
curl "http://220.121.120.83/vpn_api/release/all?ip=$(curl -s ifconfig.me)&delete=true"
```

## 🔄 재설치

서버를 재설치할 때는 그냥 다시 실행하면 됩니다:
```bash
sudo ./install_vpn_server.sh
```
- 자동으로 기존 서버 정보를 삭제하고 새로 등록
- 새로운 키 10개 생성 및 등록

## 📝 시스템 정보

- **포트**: 55555/UDP
- **내부 네트워크**: 10.8.0.0/24
- **동시 접속**: 10개
- **OS**: Rocky Linux 9 / RHEL 9 / AlmaLinux 9

---
*생성일: 2025-11-05*