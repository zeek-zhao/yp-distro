# Copilot Coding Agent Instructions — zeek-zhao/yocto

You implement issues in the Yocto multi-version engineering repo `zeek-zhao/yocto`.
For the v0.4.0 build-system demo recipes (#64-#70) follow the rules below exactly.

## 1. Git identity & commit rules (MANDATORY — repo has a commit-msg hook that REJECTS violations)
Run BEFORE every commit:
    git config user.name "zeek.zhao"
    git config user.email "zeek.zhao@foxmail.com"
- NEVER add a `Co-authored-by:` trailer. In particular NEVER add `Co-authored-by: Copilot`.
- NEVER add `Generated with ...`, `🤖`, or `Assisted by ...` to commit messages.
- Use `git commit -F <file>` for multi-line messages; never put a literal `\n` in the subject line.
- Commit message style: Conventional Commits, e.g. `feat(demo): cmake build-system template (#65)`.

## 2. Branch & PR
- Branch from `dev`. Name: `feat/<issue>-<slug>` (e.g. `feat/65-cmake`).
- Open PR against `dev` (never `main`). PR body MUST contain `Closes #<N>`.

## 3. Build-system demo recipe layout (v0.4.0)
- Directory: `layers/meta-yp/recipes-demo/yp-demo-<sys>/`, `<sys>` in {make,cmake,autotools,meson,python,rust,go}.
- Each recipe MUST `inherit yp-service` and ship a systemd unit file `yp-demo-<sys>.service`
  (the distro is systemd-only — do NOT write an init script or `/etc/init.d` file).
- Service registration uses `YP_SERVICE_NAME` / `YP_SERVICE_UNIT` (default `${PN}.service`);
  the bbclass installs it via `do_install:append` and enables via `SYSTEMD_AUTO_ENABLE`.
- In 6.0, `file://` sources unpack into `UNPACKDIR`. Set `S = "${UNPACKDIR}"`
  (do NOT use `S = "${WORKDIR}"` for 6.0; if you must, document why in the recipe comment).
- Cross-compile variables MUST come from bitbake, never hardcoded:
  - make: `oe_runmake CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"`
  - cmake/meson/autotools: rely on the inherited toolchain file; do not set CMAKE_C_COMPILER etc. by hand.
- Keep each recipe <=40 lines where practical.
- Do NOT modify `recipes-example/cpp-hello` (it is the scancode carrier).

## 4. Per-system gotchas
- cmake: `inherit cmake`; use `OECMAKE_*` not `CFLAGS`; require `cmake_minimum_required(VERSION 3.10)`.
- autotools: do NOT commit a generated `configure` (let autoreconf run); `mkdir -p ${S}/m4` in `do_configure:prepend`.
- meson: `inherit meson`; do not hardcode `c_args` in `project(default_options)`.
- python: `inherit python_setuptools_build_meta` (NOT legacy `setuptools3`); `RDEPENDS` includes python3-core + python3-json.
- rust: `inherit cargo`; offline vendor (`cargo vendor` + `.cargo/config.toml` `[source.crates-io] replace-with`); `CARGO_BUILD_FLAGS += "--offline"`.
- go: `inherit go-mod`; `GOSUMDB=off`; vendor modules; build with `-trimpath`.

## 5. Verification
- Build: `kas shell -c "bitbake yp-demo-<sys>"` (needs the release container + network).
- After build, the binary installs into the `full` image `yp-image`
  (add `yp-demo-<sys>` to `IMAGE_INSTALL` in `layers/meta-yp/recipes-core/images/yp-image.bb`)
  and `systemctl is-enabled yp-demo-<sys>` must report `enabled`.
- If you cannot run a full bitbake in this environment, still write a correct, lint-clean recipe and note the build was not executed.
