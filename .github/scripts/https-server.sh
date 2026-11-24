#!/bin/sh
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
# The HTTPS server Delivery's HTTPS probe asks (test/fixtures/https), on
# this computer, so that the check needs no network and no server
# anyone else runs:
#
#   .github/scripts/https-server.sh prepare FOLDER
#   .github/scripts/https-server.sh start FOLDER
#   .github/scripts/https-server.sh stop FOLDER
#
# prepare makes a certificate authority for this run alone, valid for
# two days, and a certificate it signs for 127.0.0.1, which a check
# that must put the authority in an app before the app is built needs
# first. start makes them too, unless FOLDER already holds them from
# prepare, then runs openssl s_server -HTTP with them on a free port
# and returns once the server accepts. FOLDER then holds ca.pem, the authority's certificate, which
# a check puts where the app's Ruby looks or nowhere, and url, the
# address to give the probe. The private keys never leave FOLDER. stop
# ends the server. Only the openssl command is needed, OpenSSL's or the
# LibreSSL macOS ships, so it runs where the app's computer has no Ruby;
# a container with no openssl gets FOLDER from its host and reaches the
# server on the host's network.

set -eu
command=${1:-}
folder=${2:-}
[ -n "$folder" ] || { echo "usage: https-server.sh prepare|start|stop FOLDER" >&2; exit 2; }

case $command in
  prepare|start) ;;
  stop)
    [ ! -s "$folder/pid" ] || kill "$(cat "$folder/pid")" 2>/dev/null || true
    rm -f "$folder/pid"
    exit 0
    ;;
  *) echo "usage: https-server.sh prepare|start|stop FOLDER" >&2; exit 2 ;;
esac

mkdir -p "$folder"
cd "$folder"
generate() {
# Subjects and extensions come from configuration files rather than
# -subj and -addext, which the LibreSSL of older macOS lacks.
cat >ca.cnf <<'CNF'
[req]
distinguished_name = subject
prompt = no
x509_extensions = authority
[subject]
CN = Fledge HTTPS probe test authority
[authority]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
CNF
cat >server.cnf <<'CNF'
[req]
distinguished_name = subject
prompt = no
[subject]
CN = 127.0.0.1
[server]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:127.0.0.1
authorityKeyIdentifier = keyid
CNF
openssl req -x509 -new -newkey rsa:2048 -nodes -days 2 -sha256 -config ca.cnf -keyout ca.key -out ca.pem 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -sha256 -config server.cnf -keyout server.key -out server.csr 2>/dev/null
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -set_serial 2 -days 2 -sha256 \
  -extfile server.cnf -extensions server -out server.pem 2>/dev/null
# The name OpenSSL looks the authority up by in a folder of hashed
# names, such as the /etc/ssl/certs update-ca-certificates writes.
openssl x509 -hash -noout -in ca.pem >./hash
}
[ -s server.pem ] || generate
[ "$command" = start ] || exit 0

# s_server -HTTP sends a file of FOLDER as it is, so the response says
# its length: -www sends a page with none and closes the connection,
# and the LibreSSL of macOS closes it with no TLS close_notify, which
# OpenSSL 3's reader of a body that runs to the end reports as an
# error ("SSL_read: unexpected eof while reading").
printf 'HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n\r\nok\n' >ok.http

# A port from this process's number, and the next ones if another
# program holds it; s_server exits at once when it cannot bind.
port=$((20000 + $$ % 20000))
for _ in 1 2 3 4 5; do
  openssl s_server -accept "$port" -cert server.pem -key server.key -HTTP >server.log 2>&1 </dev/null &
  echo $! >pid
  waited=0
  while [ "$waited" -lt 50 ]; do
    if grep -q ACCEPT server.log 2>/dev/null; then
      echo "https://127.0.0.1:$port/ok.http" >url
      echo "https-server.sh: serving $(cat url) with a certificate of a test authority made for this run"
      exit 0
    fi
    kill -0 "$(cat pid)" 2>/dev/null || break
    sleep 0.2
    waited=$((waited + 1))
  done
  kill "$(cat pid)" 2>/dev/null || true
  port=$((port + 1))
done
echo "::error::https-server.sh: openssl s_server did not start; its last words:" >&2
cat server.log >&2
exit 1
