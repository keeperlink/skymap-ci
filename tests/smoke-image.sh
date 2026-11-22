#!/usr/bin/env bash
# Smoke the exact image offline and read-only, including its non-root ci account.
set -euo pipefail

if (( $# != 3 )); then
  echo "usage: $0 IMAGE UBUNTU_VERSION PYTHON_VERSION" >&2
  exit 2
fi

image="$1"
ubuntu="$2"
python="$3"
case "$ubuntu:$python" in
  24.04:3.12|26.04:3.14) ;;
  *) echo "Unsupported Ubuntu/Python combination" >&2; exit 2 ;;
esac

docker run --rm -i \
  --network none --read-only --cap-drop ALL \
  --cap-add SETUID --cap-add SETGID \
  --security-opt no-new-privileges:true \
  --pids-limit 128 --memory 512m --cpus 1 \
  --tmpfs /tmp:rw,nosuid,nodev,size=128m \
  --entrypoint /bin/bash "$image" -s -- "$ubuntu" "$python" <<'SMOKE'
set -euo pipefail
expected_ubuntu="$1"
expected_python="$2"
. /etc/os-release
test "$ID" = ubuntu
test "$VERSION_ID" = "$expected_ubuntu"
test "$(id -u)" = 0
test "$(id -g)" = 0
getent passwd ci | grep -q "^ci:x:10001:10001:"
test -x /usr/bin/python3
python3 - "$expected_python" <<'PY'
import sys
expected = tuple(map(int, sys.argv[1].split(".")))
assert sys.version_info[:2] == expected, (sys.version_info, expected)
PY
for tool in bash git dpkg dpkg-deb visudo sudo cron crontab runuser \
            openssl rsync ssh python3 tar gzip sha256sum; do
    command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 1; }
done
for package in python3 python3-pip python3-venv sudo passwd cron \
               dpkg openssl rsync openssh-client git ca-certificates; do
    dpkg-query --show --showformat='${Status}' "$package" |
      grep -qx 'install ok installed' || { echo "Missing package: $package" >&2; exit 1; }
done
runuser -u ci -- bash -c '
  set -euo pipefail
  test "$(id -u)" = 10001
  test "$(id -g)" = 10001
  test "$HOME" = /home/ci
  python3 -c "import os,pwd; assert pwd.getpwuid(os.getuid()).pw_uid == 10001"
  python3 -m venv /tmp/smoke-venv
  /tmp/smoke-venv/bin/python -m pip --version
  test -w /tmp
  test ! -w /usr/bin
'
echo "PASS Ubuntu $expected_ubuntu Python $expected_python (root job setup, non-root validator, packages and venv)"
SMOKE
