#!/usr/bin/env bash
# Exercise GitHub runner-owned checkout and file-command paths with a real
# host bind mount. Both success and failure must restore workspace ownership.
set -euo pipefail

if (( $# != 1 )); then
  echo "usage: $0 IMAGE" >&2
  exit 2
fi

image="$1"
workspace="$(mktemp -d /tmp/skymap-ci-checkout.XXXXXX)"
commands="$(mktemp -d /tmp/skymap-ci-runner-commands.XXXXXX)"
trap 'rm -rf -- "$workspace" "$commands"' EXIT
printf 'checkout fixture\n' > "$workspace/source.txt"
printf 'runner-owned summary\n' > "$commands/summary.md"
chmod 0644 "$workspace/source.txt" "$commands/summary.md"
original_owner="$(stat -c '%u:%g' "$workspace")"
summary_owner="$(stat -c '%u:%g' "$commands/summary.md")"

for scenario in success failure; do
  result=0
  docker run --rm -i \
    --network none --read-only \
    --security-opt no-new-privileges:true \
    --pids-limit 128 --memory 512m --cpus 1 \
    --tmpfs /tmp:rw,nosuid,nodev,size=128m \
    --mount "type=bind,src=$workspace,dst=/workspace" \
    --mount "type=bind,src=$commands,dst=/runner-commands" \
    -e "SMOKE_SCENARIO=$scenario" \
    -e GITHUB_WORKSPACE=/workspace \
    -e GITHUB_STEP_SUMMARY=/runner-commands/summary.md \
    --workdir /workspace --entrypoint /bin/bash "$image" -s <<'SMOKE' || result=$?
set -euo pipefail
test "$(id -u)" = 0
original_owner="$(stat -c '%u:%g' "$GITHUB_WORKSPACE")"
ci_summary="$(mktemp /tmp/skymap-ci-summary.XXXXXX)"
cleanup() {
  status=$?
  if [[ -s "$ci_summary" ]]; then
    cat "$ci_summary" >> "$GITHUB_STEP_SUMMARY" || status=1
  fi
  chown -R "$original_owner" "$GITHUB_WORKSPACE" || status=1
  rm -f "$ci_summary" || status=1
  exit "$status"
}
trap cleanup EXIT
test -f source.txt
# A runner-owned 0644 file outside the checkout is not writable by ci.
test "$(stat -c '%a' "$GITHUB_STEP_SUMMARY")" = 644
chown ci:ci "$ci_summary"
chown -R ci:ci "$GITHUB_WORKSPACE"
runuser -u ci -- env GITHUB_STEP_SUMMARY="$ci_summary" bash -s <<'VALIDATE'
set -euo pipefail
cd "$GITHUB_WORKSPACE"
test "$(id -u)" = 10001
test "$HOME" = /home/ci
python3 -c 'import os,pwd; assert pwd.getpwuid(os.getuid()).pw_uid == 10001'
test "$GITHUB_STEP_SUMMARY" != /runner-commands/summary.md
test ! -w /runner-commands/summary.md
umask 077
mkdir -m 700 dist
echo "synthetic coverage" > dist/coverage.xml
python3 -m venv /tmp/consumer-venv
/tmp/consumer-venv/bin/python -c 'import os; assert os.geteuid() == 10001'
printf 'CI validation summary %s\n' "$SMOKE_SCENARIO" >> "$GITHUB_STEP_SUMMARY"
test -w source.txt
if [[ "$SMOKE_SCENARIO" == failure ]]; then
  exit 23
fi
VALIDATE
SMOKE

  if [[ "$scenario" == success ]]; then
    test "$result" -eq 0
  else
    test "$result" -eq 23
  fi
  # The real GitHub summary remains runner-owned and root-appended.
  test "$(stat -c '%u:%g' "$commands/summary.md")" = "$summary_owner"
  test "$(stat -c '%a' "$commands/summary.md")" = 644
  grep -q "CI validation summary $scenario" "$commands/summary.md"
  # The runner must be able to remove even 0700/0600 validator artifacts.
  test "$(stat -c '%u:%g' "$workspace")" = "$original_owner"
  test "$(stat -c '%u:%g' "$workspace/dist")" = "$original_owner"
  test "$(stat -c '%u:%g' "$workspace/dist/coverage.xml")" = "$original_owner"
  test "$(stat -c '%a' "$workspace/dist")" = 700
  test "$(stat -c '%a' "$workspace/dist/coverage.xml")" = 600
  rm -rf -- "$workspace/dist"
done

echo "PASS runner-owned 0644 summary isolation, root forwarding, and workspace restoration (success + failure)"
