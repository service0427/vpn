# VPN 시스템 메모

## 2025-11-01: 동글 VPN 추가 및 개선사항

### 완료된 작업

1. **USB 동글 VPN 추가** (wg1)
   - 인터페이스: enp0s21f0u4 (Huawei E353/E3131)
   - 로컬 IP: 192.168.18.100/24
   - 공인 IP: 110.70.55.46 (변동 가능)
   - VPN 포트: 51821
   - VPN 네트워크: 10.0.1.0/24
   - 라우팅: table 201을 통해 동글로만 트래픽 전송

2. **API 개선: 포트 구분 지원**
   - 기존: `/api/vpn/:public_ip/config` (같은 IP에 여러 VPN 있으면 첫번째만 반환)
   - 신규: `/api/vpn/:public_ip/:port/config` (포트까지 명시)
   - 하위호환: 기존 엔드포인트도 유지 (ORDER BY created_at)

3. **sync.sh 개선**
   - VPN 목록에서 public_ip + port 모두 추출
   - 새로운 API 엔드포인트 사용
   - 파일: `/home/vpn/client/sync.sh`

4. **healthcheck.sh 개선**
   - ping 대신 로컬 WireGuard 인터페이스 실제 상태 체크 (`wg show`)
   - 자신의 public_ip를 확인하여 자신의 VPN만 업데이트
   - 파일: `/home/vpn/client/healthcheck.sh`

5. **DB 스키마 변경**
   - UNIQUE 제약: `public_ip` → `(public_ip, port)`
   - 같은 IP에 여러 포트로 VPN 운영 가능

### 현재 구조

```
서버: 112.161.221.82
├─ wg0 (포트 51820)
│  └─ 메인 VPN (eno1 → 112.161.221.82)
└─ wg1 (포트 51821)
   └─ 동글 VPN (enp0s21f0u4 → 110.70.55.46)
```

### 주요 파일 위치

- 서버 설정: `/etc/wireguard/wg1.conf`
- 클라이언트 설정: `/home/vpn/wg1-client.conf`
- 동기화 스크립트: `/home/vpn/client/sync.sh`
- 헬스체크: `/home/vpn/client/healthcheck.sh`
- API 서버: `/home/proxy/scripts/toggle_api.js` (포트 80)

### 클라이언트 사용법

```bash
cd ~/vpn-ip-rotation/client

# VPN 동기화
sudo ./sync.sh

# 사용
./vpn 0 curl ifconfig.me  # wg0: 112.161.221.82
./vpn 1 curl ifconfig.me  # wg1: 112.161.209.120
./vpn 2 curl ifconfig.me  # wg2: 110.70.55.46 (동글)
```

### 알려진 이슈 및 제한사항

1. **DHCP IP 변경 문제**
   - healthcheck.sh가 IP + port만으로 자신의 VPN 식별
   - DHCP로 IP가 변경되면 다른 서버가 같은 IP를 받을 경우 충돌 가능
   - **해결방안 (미구현)**: server_id (machine-id) 사용

2. **healthcheck 동시 실행**
   - 여러 서버가 같은 IP를 사용할 경우 서로 DB 업데이트 충돌
   - 현재는 각 서버가 자신의 로컬 인터페이스만 체크하는 방식으로 완화

### 향후 개선 아이디어

#### server_id 도입 (DHCP IP 변경 안전)

**문제점:**
- 서버 A가 61.80.38.72로 VPN 등록
- DHCP로 서버 A의 IP가 61.80.38.73으로 변경
- 다른 기기(서버 B)가 61.80.38.72를 받음
- healthcheck 충돌 가능

**해결방법:**
1. DB에 `server_id VARCHAR(64)` 컬럼 추가
2. 각 서버는 `/etc/machine-id` 값을 server_id로 사용
3. healthcheck.sh에서 `WHERE server_id = '$SERVER_ID' AND port = $PORT` 조건 사용
4. UNIQUE 제약을 `(server_id, port)`로 변경
5. IP 변경시 healthcheck가 자동으로 새 IP를 DB에 업데이트

**장점:**
- DHCP로 IP 변경되어도 각 서버가 자신의 레코드만 정확히 관리
- 여러 서버가 동일 IP를 순차적으로 사용해도 충돌 없음

**구현 참고:**
```sql
ALTER TABLE vpn_servers ADD COLUMN server_id VARCHAR(64) AFTER id;
ALTER TABLE vpn_servers DROP INDEX unique_ip_port;
ALTER TABLE vpn_servers ADD UNIQUE KEY unique_server_port (server_id, port);
```

```bash
# healthcheck.sh
SERVER_ID=$(cat /etc/machine-id)
UPDATE vpn_servers SET status='active', public_ip='$MY_IP'
WHERE server_id='$SERVER_ID' AND port=$PORT
```

### 문제 발생시 체크리스트

1. **클라이언트가 VPN 연결 안됨**
   - 서버에서 `sudo wg show wg1` 확인
   - `netstat -uln | grep 51821` 확인
   - DB에서 VPN 등록 상태 확인

2. **트래픽이 동글로 안나감**
   - `ip route show table 201` 확인
   - `ip rule show` 확인
   - `curl --interface enp0s21f0u4 ifconfig.me` 테스트

3. **DB에 잘못된 VPN 등록됨**
   - 다른 서버들의 healthcheck.sh 버전 확인
   - `/home/vpn/client/healthcheck.sh` 최신 버전으로 업데이트

### 배포 체크리스트

새로운 VPN 서버 추가시:
- [ ] `/home/vpn/client/sync.sh` 최신 버전으로 업데이트
- [ ] `/home/vpn/client/healthcheck.sh` 최신 버전으로 업데이트
- [ ] crontab에 healthcheck 등록
- [ ] 서버에서 VPN 등록 API 호출 (port 포함)
