# SKY-MAP CI images

Public Ubuntu CI environments with native distribution Python and the system
utilities needed to validate [SKY-MAP host-helper](https://github.com/wikisky-org/skymap-jenkins-host).

| Docker Hub tag | Ubuntu | Native Python |
| --- | --- | --- |
| `keeperlink/skymap-ci:ubuntu24.04-py312` | 24.04 | 3.12 |
| `keeperlink/skymap-ci:ubuntu26.04-py314` | 26.04 | 3.14 |

The images provide `/usr/bin/python3`, `python3-venv`, `python3-pip`,
`dpkg-deb`, `visudo`, `cron`, `crontab`, `rsync`, SSH, OpenSSL, Git,
and standard development utilities. The image starts as **root** so the
native GitHub Actions container job can check out code and write runner-owned
file commands. A dedicated **ci account (UID/GID 10001)** is provided for
unprivileged repository validation. Each consumer explicitly switches to ci
after preparing a writable checkout. Project Python dependencies remain
outside the image, installed in a virtual environment.

## Using the image in GitHub Actions

```yaml
jobs:
  offline-py314:
    runs-on: ubuntu-24.04
    container:
      image: keeperlink/skymap-ci:ubuntu26.04-py314@sha256:REPLACE_WITH_PUBLISHED_DIGEST
    steps:
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09
        with:
          persist-credentials: false
      - name: Run pinned offline validation as non-root
        shell: bash
        run: |
          set -euo pipefail
          # Preserve the runner's workspace ownership for post-job cleanup.
          original_owner="$(stat -c '%u:%g' "$GITHUB_WORKSPACE")"
          ci_summary="$(mktemp /tmp/skymap-ci-summary.XXXXXX)"
          cleanup() {
            status=$?
            # The actual GitHub summary belongs to the runner, not uid 10001.
            if [[ -s "$ci_summary" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
              cat "$ci_summary" >> "$GITHUB_STEP_SUMMARY" || status=1
            fi
            chown -R "$original_owner" "$GITHUB_WORKSPACE" || status=1
            rm -f "$ci_summary" || status=1
            exit "$status"
          }
          trap cleanup EXIT
          chown ci:ci "$ci_summary"
          chown -R ci:ci "$GITHUB_WORKSPACE"
          runuser -u ci -- env GITHUB_STEP_SUMMARY="$ci_summary" bash -s <<'VALIDATE'
          set -euo pipefail
          cd "$GITHUB_WORKSPACE"
          python3 -m venv /tmp/ci-venv
          /tmp/ci-venv/bin/python -m pip install --only-binary=:all: -r requirements-dev.txt
          /tmp/ci-venv/bin/python tests/tools/validate.py --stage offline
          VALIDATE
```

Use **immutable registry digests** in consumers. The root job user handles
checkout and runner-owned file commands. The validation step temporarily
makes the checkout writable by `ci`, uses a dedicated writable summary file
for non-root `validate.py`, appends that summary to the GitHub-owned summary
as root, and **restores the original workspace UID/GID on exit even when
validation fails**. Do not set container.options --user 10001: GitHub
Actions manages runner-owned checkout and file-command paths. CI simulates
the read-only-to-ci summary boundary and workspace cleanup; separately verify
the published image in a native GitHub Actions container job before making
it a required check in skymap-jenkins-host.

## Local build and verification

```bash
docker build --pull -f Dockerfile \
  --build-arg UBUNTU_VERSION=26.04 \
  --build-arg EXPECTED_PYTHON=3.14 \
  -t skymap-ci-smoke:ubuntu26.04-py314 .
bash tests/smoke-image.sh skymap-ci-smoke:ubuntu26.04-py314 26.04 3.14
bash tests/smoke-consumer.sh skymap-ci-smoke:ubuntu26.04-py314
```

For Ubuntu 24.04 use `24.04`, `3.12`, and
`skymap-ci-smoke:ubuntu24.04-py312`.

## Manual Docker Hub publication

Publishing follows the test-before-push approach used by
[keeperlink/ssh-mcp](https://github.com/keeperlink/ssh-mcp/blob/main/docs/container-publishing.md).

1. Create the **public Docker Hub** repository `keeperlink/skymap-ci`.
2. Configure the GitHub environment `dockerhub-publish` with deployment
   branches restricted to **main only** (no wildcards or tags).
3. Add **environment secrets**, not repository-level secrets:
   `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (push-capable Docker Hub token).
4. After a successful current-main CI run, select
   **Actions → Publish SKY-MAP CI images → Run workflow**, on `main`.

The publication job builds both OCI indexes (including SBOM and provenance),
loads the exact runnable images for offline/non-root smoke tests and **only
then** logs in and publishes. A dispatch creates four tags:

- `ubuntu24.04-py312-v<run-number>` (immutable)
- `ubuntu24.04-py312` (moving alias)
- `ubuntu26.04-py314-v<run-number>` (immutable)
- `ubuntu26.04-py314` (moving alias)

The workflow checks numbered tags do not already exist, publishes and
digest-verifies **both immutable tags before moving either alias**, then
verifies the aliases against the corresponding immutable digests. Only
linux/amd64 is built. If an alias update fails, the aliases might still be
temporarily out of sync; reconcile remote tags and digests before retrying.
Never overwrite numbered tags.

No CI pull request or main-branch push can automatically publish an image.
