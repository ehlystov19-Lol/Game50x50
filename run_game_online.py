import subprocess
import time
import sys
import os

print("Starting Python Game Server & Cloudflare Tunnel...")

# Start server
server_proc = subprocess.Popen([sys.executable, "server.py"], cwd=os.path.dirname(os.path.abspath(__file__)))

time.sleep(2)

# Start cloudflared
cloudflared_bin = r"C:\Users\EGOR\AppData\Local\Temp\cloudflared.exe"
tunnel_proc = subprocess.Popen([cloudflared_bin, "tunnel", "--url", "http://localhost:3000"], cwd=os.path.dirname(os.path.abspath(__file__)))

print("Game server and Cloudflare tunnel are ACTIVE!")

try:
    tunnel_proc.wait()
    server_proc.wait()
except Exception:
    tunnel_proc.kill()
    server_proc.kill()
