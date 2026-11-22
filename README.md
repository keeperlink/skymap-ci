# SKY-MAP CI images

Public Ubuntu CI environments with native distribution Python and the system
utilities needed to validate [SKY-MAP host-helper](https://github.com/wikisky-org/skymap-jenkins-host).

| Docker Hub tag | Ubuntu | Native Python |
| --- | --- | --- |
| `keeperlink/skymap-ci:ubuntu24.04-py312` | 24.04 | 3.12 |
| `keeperlink/skymap-ci:ubuntu26.04-py314` | 26.04 | 3.14 |

The images provide `/usr/bin/python3`, `python3-venv`, `python3-pip`,
`dpkg-deb`, `visudo`, `cron`, `crontab`, `rsync`, SSH, OpenSSL, Git,
and standard development utilities. The default user is **non-root**
(UID/GID 10001). Repository-specific Python dependencies are deliberately
**not** installed in these images; create a venv instead.

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
      - name: Install pinned project dependencies
        run: |
          python3 -m venv /tmp/ci-venv
          /tmp/ci-venv/bin/python -m pip install --only-binary=:all: -r requirements-dev.txt
      - name: Validate under Ubuntu's own Python
        run: /tmp/ci-venv/bin/python tests/tools/validate.py --stage offline
```

Use **immutable registry digests** when consuming published images. Non-root
job-container checkout permissions must also pass real consumer CI.

## Local build and verification

```bash
docker build --pull -f Dockerfile \
  --build-arg UBUNTU_VERSION=26.04 \
  --build-arg EXPECTED_PYTHON=3.14 \
  -t skymap-ci-smoke:ubuntu26.04-py314 .
bash tests/smoke-image.sh skymap-ci-smoke:ubuntu26.04-py314 26.04 3.14
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

The workflow checks that numbered tags do not already exist and verifies
each alias has the same OCI digest as its numbered tag. Only `linux/amd64`
is built. If publication partially fails, reconcile remote tags and digests
before retrying. Never overwrite numbered tags.

No CI pull request or main-branch push can automatically publish an image.
