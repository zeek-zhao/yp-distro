# Build container

Run a release toolchain container with `scripts/container.sh --release <release>`.
The variant defaults to `general`; the machine defaults to `qemux86-64`.

The Docker container name is `yocto-<release>-<variant>`, for example
`yocto-scarthgap-general`. The machine is recorded as the
`yocto.machine=<machine>` Docker label. Containers run as the invoking host
UID:GID (`--user`); starting as root is rejected.

The host UID can differ from the image's `builder` UID (2000 on a shared build
node versus 1000 in the image). Before a real run, the script reads the image's
baseline `/etc/passwd`, replaces `builder` with the host UID:GID, and removes
any other entry using that UID. The resulting `work/home/.passwd` has mode
644 and is mounted read-only at `/etc/passwd`, so `id -un` and `getpwuid`
resolve to `builder` without changing the runtime UID. `--check` prints the
host UID:GID; neither `--check` nor `--dry-run` creates the passwd file.

The repository is mounted at `/work`. Build sources, outputs, downloads,
sstate, and the per-release home directory live under the repository's
`work/` tree (`/work/work/` in the container). `HOME` is
`/work/work/home/<release>`, `DL_DIR` is `/work/work/downloads`, and
`SSTATE_DIR` is `/work/work/sstate`. These paths keep build data on the
repository's `/home` filesystem rather than `/tmp`, the container layer, or
the user's cache. Before running, the script checks `WATERMARK_PCT` (default
85%); on failure, clear unneeded data under `work/` or adjust the threshold.

Use `scripts/container.sh --release scarthgap --check` to inspect resolved
configuration and preflight status, or add `--dry-run` to print the Docker
command as one shell-escaped line on stdout without running it (diagnostics
go to stderr). Neither mode pulls an image. Runtime prefers the
local `:local` image and pulls `:latest` only when the local image is absent.
If neither image is available, build it with
`scripts/image.sh build <release>`.

For image cleanup (#16), only use
`docker image prune --filter label=project=yocto`. **Do not use `-a`**:
The build node is a shared Jenkins agent, and unrelated images must not be removed.

When called inside the dev container, Docker still runs on the host via the
mounted socket. `WB_HOST_REPO_DIR` carries the host's absolute checkout path;
using nested `/work` as a host source could mount an empty or unrelated
directory. The path must be absolute but need not exist inside the dev
container. `dev.sh` also passes the host Docker executable and plugin source
paths as `WB_HOST_DOCKER_BIN` and `WB_HOST_DOCKER_PLUGIN_DIR`; the build
container mounts those host paths rather than mistakenly binding paths inside
the dev container.
