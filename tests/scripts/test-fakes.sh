#!/usr/bin/env bash
# Checks the fakes of the e2e bench (harness/fakes/app.py) on a local process: HEAD answers the headers of GET without a
# body, and a binary upload reaches an extra module byte for byte (SHA-256), sized or chunked, then comes back intact.
set -u
. "$(dirname "$0")/../../tools/python.sh"
HERE=$(cd "$(dirname "$0")" && pwd)
APP="$HERE/../../skills/lutece-e2e/harness/fakes/app.py"
T=$(mktemp -d)
mkdir -p "$T/extra" "$T/data"
cat > "$T/extra/blob.py" <<'PY'
import hashlib
STORE = {}
def handle(handler, method, path, body):
    if method == "PUT":
        STORE[path] = handler.raw
        return handler.send(200, hashlib.sha256(handler.raw).hexdigest())
    data = STORE.get(path)
    if data is None:
        return handler.send(404, "none")
    return handler.send(200, data, "application/octet-stream")
PREFIXES = {"/blob/": handle}
PY
read -r PORT TLS < <(python3 -c 'import socket
s=[socket.socket() for _ in range(2)]
[x.bind(("127.0.0.1",0)) for x in s]
print(*[x.getsockname()[1] for x in s])')
PORT=$PORT TLS_PORT=$TLS DATA_DIR="$T/data" EXTRA_DIR="$T/extra" python3 "$APP" > "$T/out.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null; rm -rf "$T"' EXIT
out=$(python3 - "$PORT" <<'PY'
import hashlib, http.client, os, sys, time
port = int(sys.argv[1])
for _ in range(50):
    try:
        http.client.HTTPConnection("127.0.0.1", port, timeout=2).request("GET", "/health"); break
    except OSError:
        time.sleep(0.1)
data = os.urandom(70000) + bytes(range(256)) + b"\xff\xfe\x00\xc3("
c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
c.request("HEAD", "/health"); r = c.getresponse(); b = r.read()
print(r.status, r.getheader("Content-Length"), len(b))
c.request("HEAD", "/blob/none"); r = c.getresponse(); r.read(); print(r.status)
c.request("PUT", "/blob/a", body=data); r = c.getresponse(); print(r.read().decode() == hashlib.sha256(data).hexdigest())
c.request("PUT", "/blob/b", body=iter([data[:1000], data[1000:]]), encode_chunked=True)
r = c.getresponse(); print(r.read().decode() == hashlib.sha256(data).hexdigest())
c.request("GET", "/blob/b"); r = c.getresponse(); print(hashlib.sha256(r.read()).hexdigest() == hashlib.sha256(data).hexdigest())
c.request("HEAD", "/blob/a"); r = c.getresponse(); print(r.status, r.getheader("Content-Length") == str(len(data)), len(r.read()))
c.request("GET", "/health"); r = c.getresponse(); print(r.status, r.read().decode())
PY
)
expected="200 2 0
404
True
True
True
200 True 0
200 ok"
if [ "$out" = "$expected" ]; then echo "PASS: fakes answer HEAD without a body and keep a binary upload byte for byte"; exit 0; fi
echo "FAIL: fakes HEAD or binary upload"; echo "$out"; cat "$T/out.log" | tail -20; exit 1
