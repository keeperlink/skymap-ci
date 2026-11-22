#!/usr/bin/env bash
# Simulate a GitHub Actions runner-owned bind-mounted workspace before publication.
set -euo pipefail

if (( $# != 1 )); then
  echo "usage: $0 IMAGE" >&2
  exit 2
fi

image="$1"
workspace="$(mktemp -d /tmp/skymap-ci-checkout.XXXXXX)"
trap 'rm -rf -- "$workspace"' EXIT
printf 'checkout fixture\n' > "$workspace/source.txt"
printf 'runner-owned summary\n' > "$workspace/summary.txt"
chmod 0644 "$workspace/source.txt" "$workspace/summary.txt"

docker run --rm -i \
  --network none --read-only \
  --security-opt no-new-privileges:true \
  --pids-limit 128 --memory 512m --cpus 1 \
  --tmpfs /tmp:rw,nosuid,nodev,size=128m \
  --mount "type=bind,src=$workspace,dst=/workspace" \
  --workdir /workspace --entrypoint /bin/bash "$image" -s <<'SMOKE'
set -euo pipefail
test "$(id -u)" = 0
original_uid="$(stat -c %u /workspace)"
original_gid="$(stat -c %g /workspace)"
trap 'chown -R "$original_uid:$original_gid" /workspace' EXIT
# GitHub Actions checkout and file-command writes must work as the job user.
test -f source.txt
printf 'job-container summary write\n' >> summary.txt
chown -R ci:ci /workspace
# Application validation runs unprivileged against its writable checkout.
runuser -u ci -- bash -c '
  set -euo pipefail
  cd /workspace
  test "$(id -u)" = 10001
  test "$HOME" = /home/ci
  python3 -c "import os,pwd; assert pwd.getpwuid(os.getuid()).pw_uid == 10001"
  mkdir dist
  echo "synthetic coverage" > dist/coverage.xml
  python3 -m venv /tmp/consumer-venv
  /tmp/consumer-venv/bin/python -c "import os; assert os.geteuid() == 10001"
  test -w source.txt
'
test -f dist/coverage.xml
SMOKE

grep -q 'job-container summary write' "$workspace/summary.txt"
test -f "$workspace/dist/coverage.xml"
echo "PASS runner-owned checkout + root file commands + ci-owned validation output"
