"""THROWAWAY UI PROTOTYPE: python3 run.py [--port 8840]. No persistent state."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser(description="打开共笔交互模式界面原型")
parser.add_argument("--port", type=int, default=8840)
args = parser.parse_args()
directory = str(Path(__file__).resolve().parent)
server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(SimpleHTTPRequestHandler, directory=directory))
print(f"共笔原型：http://127.0.0.1:{server.server_port}/?variant=A", flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    server.server_close()
