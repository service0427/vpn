# VPN + SOCKS5 API 서버 구축 가이드

## 개요
DB 서버(220.121.120.83)에 VPN+SOCKS5 통합 관리 API를 구축하는 가이드입니다.

**API Base URL**: `http://220.121.120.83/vpn_socks5/api`

---

## 1. DB 스키마

### 1.1 기존 테이블 확인 및 수정

```sql
-- vpn_servers 테이블이 이미 있다면 SOCKS5 컬럼 추가
ALTER TABLE vpn_servers
ADD COLUMN socks5_port INT DEFAULT NULL AFTER port,
ADD COLUMN socks5_username VARCHAR(255) DEFAULT NULL,
ADD COLUMN socks5_password VARCHAR(255) DEFAULT NULL,
ADD INDEX idx_public_ip_port (public_ip, port),
ADD INDEX idx_is_active (is_active),
ADD INDEX idx_updated_at (updated_at);

-- 기존 테이블이 없다면 새로 생성
CREATE TABLE IF NOT EXISTS vpn_servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    public_ip VARCHAR(45) NOT NULL,
    port INT NOT NULL DEFAULT 55555,
    socks5_port INT DEFAULT NULL,
    socks5_username VARCHAR(255) DEFAULT NULL,
    socks5_password VARCHAR(255) DEFAULT NULL,
    is_active TINYINT(1) DEFAULT 1,
    client_config TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_ip_port (public_ip, port),
    INDEX idx_is_active (is_active),
    INDEX idx_updated_at (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

### 1.2 테스트 데이터 확인

```sql
-- 현재 등록된 VPN 서버 확인
SELECT public_ip, port, socks5_port, is_active,
       TIMESTAMPDIFF(MINUTE, updated_at, NOW()) as minutes_since_update
FROM vpn_servers
WHERE is_active = 1
ORDER BY updated_at DESC;
```

---

## 2. API 엔드포인트 구현

### 2.1 PHP 구현 (권장 - 간단함)

#### 파일 구조
```
/var/www/html/vpn_socks5/
├── api/
│   ├── register.php
│   ├── heartbeat.php
│   ├── list.php
│   └── config.php
├── config.php (DB 설정)
└── .htaccess
```

#### `/var/www/html/vpn_socks5/config.php`
```php
<?php
// DB 연결 설정
define('DB_HOST', '220.121.120.83');
define('DB_USER', 'vpnuser');
define('DB_PASS', 'vpn1324');
define('DB_NAME', 'vpn');

function getDBConnection() {
    $mysqli = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);

    if ($mysqli->connect_error) {
        http_response_code(500);
        die(json_encode(['error' => 'Database connection failed']));
    }

    $mysqli->set_charset('utf8mb4');
    return $mysqli;
}

function jsonResponse($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}
?>
```

#### `/var/www/html/vpn_socks5/api/register.php`
```php
<?php
require_once '../config.php';

// POST만 허용
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(['error' => 'Method not allowed'], 405);
}

// JSON 입력 받기
$input = json_decode(file_get_contents('php://input'), true);

if (!isset($input['public_ip'])) {
    jsonResponse(['success' => false, 'error' => 'public_ip is required'], 400);
}

$public_ip = $input['public_ip'];
$port = $input['port'] ?? 55555;
$socks5_port = $input['socks5_port'] ?? null;
$socks5_username = $input['socks5_username'] ?? null;
$socks5_password = $input['socks5_password'] ?? null;
$client_config = $input['client_config'] ?? null;

$db = getDBConnection();

$stmt = $db->prepare("
    INSERT INTO vpn_servers
        (public_ip, port, socks5_port, socks5_username, socks5_password, is_active, client_config)
    VALUES (?, ?, ?, ?, ?, 1, ?)
    ON DUPLICATE KEY UPDATE
        socks5_port = VALUES(socks5_port),
        socks5_username = VALUES(socks5_username),
        socks5_password = VALUES(socks5_password),
        client_config = VALUES(client_config),
        updated_at = CURRENT_TIMESTAMP
");

$stmt->bind_param('siisss', $public_ip, $port, $socks5_port, $socks5_username, $socks5_password, $client_config);

if ($stmt->execute()) {
    jsonResponse([
        'success' => true,
        'vpn_ip' => $public_ip,
        'vpn_port' => $port,
        'socks5_port' => $socks5_port
    ]);
} else {
    jsonResponse(['success' => false, 'error' => $stmt->error], 500);
}

$stmt->close();
$db->close();
?>
```

#### `/var/www/html/vpn_socks5/api/heartbeat.php`
```php
<?php
require_once '../config.php';

// POST만 허용
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(['error' => 'Method not allowed'], 405);
}

// JSON 입력 받기
$input = json_decode(file_get_contents('php://input'), true);

if (!isset($input['public_ip']) || !isset($input['port'])) {
    jsonResponse(['success' => false, 'error' => 'public_ip and port are required'], 400);
}

$public_ip = $input['public_ip'];
$port = $input['port'];

$db = getDBConnection();

$stmt = $db->prepare("
    UPDATE vpn_servers
    SET updated_at = CURRENT_TIMESTAMP
    WHERE public_ip = ? AND port = ?
");

$stmt->bind_param('si', $public_ip, $port);

if ($stmt->execute()) {
    if ($stmt->affected_rows > 0) {
        jsonResponse(['success' => true]);
    } else {
        jsonResponse(['success' => false, 'error' => 'VPN server not found'], 404);
    }
} else {
    jsonResponse(['success' => false, 'error' => $stmt->error], 500);
}

$stmt->close();
$db->close();
?>
```

#### `/var/www/html/vpn_socks5/api/list.php`
```php
<?php
require_once '../config.php';

$db = getDBConnection();

$result = $db->query("
    SELECT public_ip, port, socks5_port, socks5_username,
           TIMESTAMPDIFF(MINUTE, updated_at, NOW()) as minutes_since_update
    FROM vpn_servers
    WHERE is_active = 1
    ORDER BY created_at
");

$vpns = [];
while ($row = $result->fetch_assoc()) {
    $vpns[] = [
        'public_ip' => $row['public_ip'],
        'port' => (int)$row['port'],
        'socks5_port' => $row['socks5_port'] ? (int)$row['socks5_port'] : null,
        'socks5_username' => $row['socks5_username'],
        'minutes_since_update' => (int)$row['minutes_since_update']
    ];
}

jsonResponse(['vpns' => $vpns]);

$db->close();
?>
```

#### `/var/www/html/vpn_socks5/api/config.php`
```php
<?php
require_once '../config.php';

// URL: /vpn_socks5/api/config.php?ip=112.161.209.120&port=55555
$public_ip = $_GET['ip'] ?? null;
$port = $_GET['port'] ?? null;

if (!$public_ip || !$port) {
    jsonResponse(['error' => 'ip and port parameters required'], 400);
}

$db = getDBConnection();

$stmt = $db->prepare("
    SELECT client_config
    FROM vpn_servers
    WHERE public_ip = ? AND port = ? AND is_active = 1
    LIMIT 1
");

$stmt->bind_param('si', $public_ip, $port);
$stmt->execute();
$result = $stmt->get_result();

if ($row = $result->fetch_assoc()) {
    if ($row['client_config']) {
        header('Content-Type: text/plain');
        echo $row['client_config'];
    } else {
        jsonResponse(['error' => 'Config not found'], 404);
    }
} else {
    jsonResponse(['error' => 'VPN server not found'], 404);
}

$stmt->close();
$db->close();
?>
```

#### `/var/www/html/vpn_socks5/.htaccess`
```apache
# URL Rewrite 설정 (선택 사항)
RewriteEngine On

# CORS 허용
Header set Access-Control-Allow-Origin "*"
Header set Access-Control-Allow-Methods "GET, POST, OPTIONS"
Header set Access-Control-Allow-Headers "Content-Type"

# Pretty URLs
RewriteRule ^api/register$ api/register.php [L]
RewriteRule ^api/heartbeat$ api/heartbeat.php [L]
RewriteRule ^api/list$ api/list.php [L]
RewriteRule ^api/config$ api/config.php [L]
```

---

### 2.2 Node.js 구현 (선택)

#### `package.json`
```json
{
  "name": "vpn-socks5-api",
  "version": "1.0.0",
  "dependencies": {
    "mysql2": "^3.0.0"
  }
}
```

#### `vpn_api_server.js`
```javascript
const http = require('http');
const mysql = require('mysql2');

const PORT = 8080;

function getDBConnection() {
    return mysql.createConnection({
        host: '220.121.120.83',
        user: 'vpnuser',
        password: 'vpn1324',
        database: 'vpn'
    });
}

const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname;

    // CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');

    // POST /vpn_socks5/api/register
    if (pathname === '/vpn_socks5/api/register' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk.toString());
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                const db = getDBConnection();

                const query = `
                    INSERT INTO vpn_servers
                        (public_ip, port, socks5_port, socks5_username, socks5_password, is_active, client_config)
                    VALUES (?, ?, ?, ?, ?, 1, ?)
                    ON DUPLICATE KEY UPDATE
                        socks5_port = VALUES(socks5_port),
                        socks5_username = VALUES(socks5_username),
                        socks5_password = VALUES(socks5_password),
                        client_config = VALUES(client_config),
                        updated_at = CURRENT_TIMESTAMP
                `;

                db.query(query, [
                    data.public_ip,
                    data.port || 55555,
                    data.socks5_port || null,
                    data.socks5_username || null,
                    data.socks5_password || null,
                    data.client_config || null
                ], (error, results) => {
                    db.end();
                    if (error) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ success: false, error: error.message }));
                    } else {
                        res.writeHead(200);
                        res.end(JSON.stringify({
                            success: true,
                            vpn_ip: data.public_ip,
                            vpn_port: data.port || 55555,
                            socks5_port: data.socks5_port
                        }));
                    }
                });
            } catch (e) {
                res.writeHead(400);
                res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
            }
        });
        return;
    }

    // POST /vpn_socks5/api/heartbeat
    if (pathname === '/vpn_socks5/api/heartbeat' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk.toString());
        req.on('end', () => {
            try {
                const data = JSON.parse(body);
                const db = getDBConnection();

                const query = 'UPDATE vpn_servers SET updated_at = CURRENT_TIMESTAMP WHERE public_ip = ? AND port = ?';

                db.query(query, [data.public_ip, data.port], (error, results) => {
                    db.end();
                    if (error) {
                        res.writeHead(500);
                        res.end(JSON.stringify({ success: false, error: error.message }));
                    } else if (results.affectedRows === 0) {
                        res.writeHead(404);
                        res.end(JSON.stringify({ success: false, error: 'VPN server not found' }));
                    } else {
                        res.writeHead(200);
                        res.end(JSON.stringify({ success: true }));
                    }
                });
            } catch (e) {
                res.writeHead(400);
                res.end(JSON.stringify({ success: false, error: 'Invalid JSON' }));
            }
        });
        return;
    }

    // GET /vpn_socks5/api/list
    if (pathname === '/vpn_socks5/api/list') {
        const db = getDBConnection();
        db.query(`
            SELECT public_ip, port, socks5_port, socks5_username,
                   TIMESTAMPDIFF(MINUTE, updated_at, NOW()) as minutes_since_update
            FROM vpn_servers
            WHERE is_active = 1
            ORDER BY created_at
        `, (error, results) => {
            db.end();
            if (error) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: error.message }));
            } else {
                res.writeHead(200);
                res.end(JSON.stringify({ vpns: results }));
            }
        });
        return;
    }

    // 404
    res.writeHead(404);
    res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
    console.log(`VPN API Server running on port ${PORT}`);
});
```

---

## 3. 클라이언트 수정 사항

### 3.1 `/home/vpn/server/setup.sh` 수정

```bash
# 기존 (line 298)
API_HOST="112.161.221.82"

# 변경 후
API_HOST="220.121.120.83"
API_ENDPOINT="/vpn_socks5/api/register"

# API 호출 부분 (line 323-325)
# 기존
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://$API_HOST/api/vpn/register \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD")

# 변경 후 (SOCKS5 정보 포함)
API_PAYLOAD=$(cat <<EOF
{
    "public_ip": "$PUBLIC_IP",
    "port": 55555,
    "socks5_port": 10000,
    "socks5_username": "techb",
    "socks5_password": "Tech1324!@",
    "client_config": $CLIENT_CONFIG_ESCAPED
}
EOF
)

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://$API_HOST$API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d "$API_PAYLOAD")
```

### 3.2 `/home/vpn/client/healthcheck.sh` 수정

```bash
# 기존 (line 8)
API_HOST="112.161.221.82"

# 변경 후
API_HOST="220.121.120.83"
API_ENDPOINT="/vpn_socks5/api/heartbeat"

# API 호출 부분 (line 42-44)
# 기존
RESPONSE=$(curl -s -m 5 -X POST http://$API_HOST/api/vpn/heartbeat \
    -H "Content-Type: application/json" \
    -d "{\"public_ip\":\"$MY_IP\",\"port\":$PORT}" 2>&1)

# 변경 후
RESPONSE=$(curl -s -m 5 -X POST http://$API_HOST$API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d "{\"public_ip\":\"$MY_IP\",\"port\":$PORT}" 2>&1)
```

---

## 4. 설치 및 테스트

### 4.1 PHP API 설치 (Apache/Nginx)

#### Apache 설정
```bash
# 1. 디렉토리 생성
mkdir -p /var/www/html/vpn_socks5/api

# 2. 파일 복사 (위의 PHP 파일들)
# config.php, api/*.php, .htaccess

# 3. 권한 설정
chown -R apache:apache /var/www/html/vpn_socks5
chmod 755 /var/www/html/vpn_socks5
chmod 644 /var/www/html/vpn_socks5/api/*.php

# 4. Apache 재시작
systemctl restart httpd
```

#### Nginx 설정 (선택)
```nginx
server {
    listen 80;
    server_name 220.121.120.83;
    root /var/www/html;
    index index.php;

    location /vpn_socks5/api/ {
        try_files $uri $uri/ /vpn_socks5/api/router.php?$query_string;

        location ~ \.php$ {
            fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }
    }
}
```

### 4.2 Node.js API 설치 (선택)

```bash
# 1. 디렉토리 생성
mkdir -p /opt/vpn-api
cd /opt/vpn-api

# 2. 파일 생성
# vpn_api_server.js, package.json

# 3. 의존성 설치
npm install

# 4. systemd 서비스 생성
cat > /etc/systemd/system/vpn-api.service <<'EOF'
[Unit]
Description=VPN SOCKS5 API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vpn-api
ExecStart=/usr/bin/node /opt/vpn-api/vpn_api_server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. 서비스 시작
systemctl daemon-reload
systemctl enable vpn-api
systemctl start vpn-api
```

### 4.3 API 테스트

```bash
# 1. 등록 테스트
curl -X POST http://220.121.120.83/vpn_socks5/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "public_ip": "1.2.3.4",
    "port": 55555,
    "socks5_port": 10000,
    "socks5_username": "techb",
    "socks5_password": "Tech1324!@",
    "client_config": "[Interface]\nPrivateKey=test\n"
  }'

# 예상 응답:
# {"success":true,"vpn_ip":"1.2.3.4","vpn_port":55555,"socks5_port":10000}

# 2. 헬스체크 테스트
curl -X POST http://220.121.120.83/vpn_socks5/api/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"public_ip":"1.2.3.4","port":55555}'

# 예상 응답:
# {"success":true}

# 3. 목록 조회 테스트
curl http://220.121.120.83/vpn_socks5/api/list

# 예상 응답:
# {"vpns":[{"public_ip":"1.2.3.4","port":55555,"socks5_port":10000,"socks5_username":"techb","minutes_since_update":0}]}

# 4. 설정 다운로드 테스트
curl "http://220.121.120.83/vpn_socks5/api/config.php?ip=1.2.3.4&port=55555"

# 예상 응답: WireGuard 설정 파일 내용
```

---

## 5. 보안 고려사항

### 5.1 IP 화이트리스트 (권장)

```php
// config.php 상단에 추가
$allowed_ips = [
    '112.161.221.82',  // 기존 API 서버
    '112.161.209.120', // VPN 서버 1
    '112.161.221.53',  // VPN 서버 2
    // ... 추가 VPN 서버 IP
];

$client_ip = $_SERVER['REMOTE_ADDR'];
if (!in_array($client_ip, $allowed_ips)) {
    jsonResponse(['error' => 'Access denied'], 403);
}
```

### 5.2 API 키 인증 (선택)

```php
// 헤더로 API 키 전달
$api_key = $_SERVER['HTTP_X_API_KEY'] ?? '';
if ($api_key !== 'your-secret-api-key-here') {
    jsonResponse(['error' => 'Invalid API key'], 401);
}
```

---

## 6. 모니터링

### 6.1 죽은 VPN 감지 쿼리

```sql
-- 5분 이상 업데이트 안된 VPN (죽은 것으로 간주)
SELECT public_ip, port, socks5_port,
       TIMESTAMPDIFF(MINUTE, updated_at, NOW()) as minutes_dead
FROM vpn_servers
WHERE is_active = 1
  AND updated_at < DATE_SUB(NOW(), INTERVAL 5 MINUTE)
ORDER BY updated_at;
```

### 6.2 헬스체크 로그 분석

```bash
# VPN 서버에서 헬스체크 로그 확인
tail -f /var/log/vpn-healthcheck.log

# 실패한 heartbeat 찾기
grep "❌ Heartbeat 실패" /var/log/vpn-healthcheck.log
```

---

## 7. 마이그레이션 체크리스트

- [ ] DB 스키마 생성/수정 완료
- [ ] PHP API 파일 생성 및 권한 설정
- [ ] Apache/Nginx 설정 및 재시작
- [ ] API 엔드포인트 테스트 (register, heartbeat, list, config)
- [ ] `/home/vpn/server/setup.sh` API_HOST 변경
- [ ] `/home/vpn/client/healthcheck.sh` API_HOST 변경
- [ ] 기존 VPN 서버에서 healthcheck 수동 실행 테스트
- [ ] 신규 VPN 서버 설치 테스트
- [ ] 헬스체크 크론 동작 확인 (5분 대기)
- [ ] DB에서 updated_at 업데이트 확인

---

## 8. 롤백 계획

문제 발생 시 기존 API로 롤백:

```bash
# setup.sh 롤백
sed -i 's|API_HOST="220.121.120.83"|API_HOST="112.161.221.82"|g' /home/vpn/server/setup.sh
sed -i 's|API_ENDPOINT="/vpn_socks5/api/register"|# API_ENDPOINT removed|g' /home/vpn/server/setup.sh
sed -i 's|http://$API_HOST$API_ENDPOINT|http://$API_HOST/api/vpn/register|g' /home/vpn/server/setup.sh

# healthcheck.sh 롤백
sed -i 's|API_HOST="220.121.120.83"|API_HOST="112.161.221.82"|g' /home/vpn/client/healthcheck.sh
sed -i 's|API_ENDPOINT="/vpn_socks5/api/heartbeat"|# API_ENDPOINT removed|g' /home/vpn/client/healthcheck.sh
sed -i 's|http://$API_HOST$API_ENDPOINT|http://$API_HOST/api/vpn/heartbeat|g' /home/vpn/client/healthcheck.sh

# Git 커밋으로 롤백
git revert HEAD
```

---

## 요약

1. **DB 작업**: `vpn_servers` 테이블에 SOCKS5 컬럼 추가
2. **API 구축**: PHP로 4개 엔드포인트 구현 (register, heartbeat, list, config)
3. **클라이언트 수정**: setup.sh와 healthcheck.sh의 API_HOST 변경
4. **테스트**: curl로 모든 엔드포인트 동작 확인
5. **배포**: 기존 VPN 서버들에 변경사항 적용 (git pull)

**다음 단계**: 이 가이드대로 DB 서버에 API를 구축하신 후, 테스트 결과를 공유해주시면 setup.sh와 healthcheck.sh를 실제로 수정해드리겠습니다.
