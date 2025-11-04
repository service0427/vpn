#!/usr/bin/env python3
"""
SOCKS5 Proxy Server with IP Whitelist
Port: 10000
Whitelist: /home/vpn/server/socks5-whitelist.json
Update: ./update-whitelist.sh
"""

import socket
import select
import struct
import threading
import sys
import signal
import logging
import json
import os

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - SOCKS5 - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 화이트리스트 파일
WHITELIST_FILE = "/home/vpn/server/socks5-whitelist.json"

class IPWhitelist:
    def __init__(self):
        self.allowed_ips = set()
        self.load_whitelist()

    def load_whitelist(self):
        """로컬 JSON 파일에서 화이트리스트 로드"""
        if not os.path.exists(WHITELIST_FILE):
            logger.error(f"Whitelist file not found: {WHITELIST_FILE}")
            logger.error("Run './update-whitelist.sh' to create whitelist")
            return

        try:
            with open(WHITELIST_FILE, 'r') as f:
                data = json.load(f)
                self.allowed_ips = set(data.get('allowed_ips', []))
                updated_at = data.get('updated_at', 'unknown')
                logger.info(f"Whitelist loaded: {len(self.allowed_ips)} IPs (updated: {updated_at})")
        except Exception as e:
            logger.error(f"Failed to load whitelist: {e}")

    def is_allowed(self, ip):
        """IP가 화이트리스트에 있는지 확인"""
        return ip in self.allowed_ips

class SOCKS5Server:
    def __init__(self, port=10000):
        self.port = port
        self.running = True
        self.server_socket = None
        self.whitelist = IPWhitelist()

    def start(self):
        """프록시 서버 시작"""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(128)
            logger.info(f"SOCKS5 proxy with auth listening on port {self.port}")

            while self.running:
                try:
                    readable, _, _ = select.select([self.server_socket], [], [], 1)
                    if readable:
                        client_socket, address = self.server_socket.accept()
                        thread = threading.Thread(target=self.handle_client, args=(client_socket, address))
                        thread.daemon = True
                        thread.start()
                except Exception as e:
                    if self.running:
                        logger.error(f"Error accepting connection: {e}")

        except Exception as e:
            logger.error(f"Failed to start server on port {self.port}: {e}")
        finally:
            self.stop()

    def handle_client(self, client_socket, address):
        """클라이언트 연결 처리"""
        client_ip = address[0]

        try:
            # IP 화이트리스트 체크
            if not self.whitelist.is_allowed(client_ip):
                logger.warning(f"IP not in whitelist: {client_ip}")
                client_socket.close()
                return

            logger.info(f"Accepted connection from {client_ip}")

            # SOCKS5 버전 및 인증 방법 협상
            data = client_socket.recv(2)
            if len(data) < 2:
                client_socket.close()
                return

            version, nmethods = struct.unpack("!BB", data)
            if version != 5:
                client_socket.close()
                return

            # 클라이언트가 지원하는 인증 방법 읽기
            methods = client_socket.recv(nmethods)

            # 인증 불필요 (0x00)
            client_socket.send(b"\x05\x00")  # No authentication required

            # 연결 요청
            data = client_socket.recv(4)
            if len(data) < 4:
                client_socket.close()
                return

            version, cmd, _, atyp = struct.unpack("!BBBB", data)

            if cmd != 1:  # CONNECT only
                client_socket.send(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
                client_socket.close()
                return

            # 주소 파싱
            if atyp == 1:  # IPv4
                addr = socket.inet_ntoa(client_socket.recv(4))
            elif atyp == 3:  # Domain
                addr_len = client_socket.recv(1)[0]
                addr = client_socket.recv(addr_len).decode()
            else:
                client_socket.send(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
                client_socket.close()
                return

            port = struct.unpack("!H", client_socket.recv(2))[0]

            # 원격 서버 연결 (메인 이더넷 사용)
            try:
                remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                remote_socket.settimeout(10)
                remote_socket.connect((addr, port))

                # 성공 응답
                client_socket.send(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
                logger.debug(f"Connected to {addr}:{port}")

                # 데이터 중계
                self.relay_data(client_socket, remote_socket)

            except Exception as e:
                logger.debug(f"Failed to connect to {addr}:{port} - {e}")
                client_socket.send(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")

        except Exception as e:
            logger.debug(f"Error handling client: {e}")
        finally:
            client_socket.close()

    def relay_data(self, client_socket, remote_socket):
        """클라이언트와 원격 서버 간 데이터 중계"""
        try:
            client_socket.setblocking(False)
            remote_socket.setblocking(False)

            while self.running:
                ready = select.select([client_socket, remote_socket], [], [], 1)
                if ready[0]:
                    for sock in ready[0]:
                        data = sock.recv(4096)
                        if not data:
                            return
                        if sock is client_socket:
                            remote_socket.sendall(data)
                        else:
                            client_socket.sendall(data)
        except:
            pass
        finally:
            remote_socket.close()

    def stop(self):
        """서버 중지"""
        self.running = False
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass
            logger.info(f"SOCKS5 proxy stopped on port {self.port}")

def main():
    server = SOCKS5Server(port=10000)

    def signal_handler(sig, frame):
        logger.info("Shutting down...")
        server.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    server.start()

if __name__ == '__main__':
    main()
