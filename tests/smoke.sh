#!/bin/sh
# Smoke tests for hyperd. The server must already be running:
#
#   make run            # in one terminal
#   sh tests/smoke.sh   # in another
#
# Override the target with HOST=... PORT=... sh tests/smoke.sh
set -u

HOST=${HOST:-localhost}
PORT=${PORT:-8080}
URL="http://$HOST:$PORT/"
TIMEOUT=2               # seconds per request; a hung server fails instead of blocking

pass=0
fail=0

ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '     %s\n' "$2"; }

# Send raw bytes with nc. -w bounds the wait; the server closes after replying.
raw() { printf "$1" | nc -w "$TIMEOUT" "$HOST" "$PORT"; }

# --- 0. Is anything listening? ----------------------------------------------
if ! curl -s -o /dev/null --max-time "$TIMEOUT" "$URL"; then
    echo "no server at $URL (start it with 'make run')" >&2
    exit 2
fi

# --- 1. Status line and body ------------------------------------------------
status=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$URL")
[ "$status" = 200 ] && ok "GET / returns 200" || bad "GET / returns 200" "got $status"

body=$(curl -s --max-time "$TIMEOUT" "$URL")
[ "$body" = "Hello, world!" ] && ok "body is 'Hello, world!'" || bad "body" "got '$body'"

# --- 2. Headers -------------------------------------------------------------
# curl -D - dumps headers; tr strips the \r so grep sees clean lines.
headers=$(curl -s -D - -o /dev/null --max-time "$TIMEOUT" "$URL" | tr -d '\r')

echo "$headers" | grep -qi '^Content-Type: text/plain' \
    && ok "Content-Type: text/plain" || bad "Content-Type header missing"
echo "$headers" | grep -qi '^Connection: close' \
    && ok "Connection: close" || bad "Connection header missing"

# Content-Length must match the bytes actually sent, or clients hang/truncate.
clen=$(echo "$headers" | sed -n 's/^[Cc]ontent-[Ll]ength: *//p')
got=$(curl -s -o /dev/null -w '%{size_download}' --max-time "$TIMEOUT" "$URL")
[ -n "$clen" ] && [ "$clen" = "$got" ] \
    && ok "Content-Length ($clen) matches body size" \
    || bad "Content-Length matches body size" "header='$clen' downloaded=$got"

# --- 3. Raw request over nc: line endings must be CRLF ----------------------
first=$(raw 'GET / HTTP/1.1\r\nHost: x\r\n\r\n' | head -n 1)
case "$first" in
    "HTTP/1.1 200 OK"$(printf '\r')) ok "raw status line ends in CRLF" ;;
    *) bad "raw status line ends in CRLF" "got '$(printf '%s' "$first" | od -c | head -n 1)'" ;;
esac

# --- 4. Robustness: server must survive hostile clients ---------------------
# Milestone 1 doesn't parse, so we only check the server is still alive after.
raw '\001\002garbage\377\n' > /dev/null
raw 'GET / HTTP/1.1\r\nHo' > /dev/null              # half-sent request
nc -w 1 "$HOST" "$PORT" < /dev/null > /dev/null      # connect, send nothing, leave

status=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$URL")
[ "$status" = 200 ] && ok "still serving after hostile clients" \
    || bad "still serving after hostile clients" "got $status"

# --- 5. Many sequential connections (fd leak check) --------------------------
# If cfd is never closed, the server runs out of descriptors (ulimit -n).
i=0; n_ok=0; N=200
while [ "$i" -lt "$N" ]; do
    s=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$URL")
    [ "$s" = 200 ] && n_ok=$((n_ok + 1))
    i=$((i + 1))
done
[ "$n_ok" = "$N" ] && ok "$N sequential requests" || bad "$N sequential requests" "$n_ok/$N ok"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
