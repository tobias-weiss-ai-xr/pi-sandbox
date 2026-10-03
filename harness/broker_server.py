#!/usr/bin/env python3
"""Secret broker for the pi-sandbox probe — poor-man's Docker Sandboxes.

Serves ONE demo credential to any caller bearing the scope token. This is the
sbx proxy pattern: the real key stays on the host, the container holds a
placeholder and pulls the key at runtime over one forwarded port.

SAFETY: serves a DEMO credential only (BROKER_DEMO_KEY); logs request lines
without bodies. Binds to the Docker bridge gateway (172.17.0.1) so only
containers can reach it.
"""
import http.server
import os
import sys

TOKEN = os.environ.get("BROKER_TOKEN", "dev-token")
KEY = os.environ.get("BROKER_DEMO_KEY", "demo-real-key-1a2b3c")
BIND = os.environ.get("BROKER_BIND", "172.17.0.1")  # Docker bridge gateway by default


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/key":
            self.send_error(404)
            return
        if self.headers.get("X-Scope-Token") != TOKEN:
            self.send_error(403)
            return
        body = KEY.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    port = int(os.environ.get("BROKER_PORT", "18080"))
    http.server.ThreadingHTTPServer((BIND, port), Handler).serve_forever()