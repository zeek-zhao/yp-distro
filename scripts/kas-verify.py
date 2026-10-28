#!/usr/bin/env python3
"""Statically validate kas targets without checking out repositories."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Any

import yaml


TOP_LEVEL_FIELDS = {
    "header",
    "machine",
    "distro",
    "target",
    "repos",
    "local_conf_header",
    "bblayers_conf_header",
    "env",
    "defaults",
    "overrides",
    "build_system",
    "task",
    "proxy_config",
    "menu_configuration",
    "artifacts",
}
REPO_FIELDS = {
    "name",
    "url",
    "type",
    "commit",
    "branch",
    "tag",
    "refspec",
    "path",
    "layers",
    "patches",
}
RELEASES = ("dunfell", "kirkstone", "scarthgap", "wrynose")
VARIANTS = ("general", "custom")
REPO_ENV_KEYS = {
    "poky": ("POKY_TAG",),
    "openembedded-core": ("OE_CORE_TAG",),
    "bitbake": ("BITBAKE_TAG",),
    "meta-yocto": ("META_YOCTO_TAG",),
}


class VerificationError(Exception):
    """A configuration or invariant failed validation."""


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        content = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise VerificationError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(content, dict):
        raise VerificationError(f"{path} must contain a YAML mapping")
    return content


def validate_builtin_schema(config: dict[str, Any], path: Path) -> None:
    unknown = set(config) - TOP_LEVEL_FIELDS
    if unknown:
        raise VerificationError(
            f"{path} has unsupported top-level fields: "
            f"{', '.join(sorted(unknown))}"
        )

    header = config.get("header")
    if not isinstance(header, dict):
        raise VerificationError(f"{path}: header must be a mapping")
    if header.get("version") != 14:
        raise VerificationError(f"{path}: header.version must be 14")
    includes = header.get("includes", [])
    if not isinstance(includes, list) or not all(
        isinstance(include, str) for include in includes
    ):
        raise VerificationError(
            f"{path}: header.includes must be a list of strings"
        )

    repos = config.get("repos", {})
    if not isinstance(repos, dict):
        raise VerificationError(f"{path}: repos must be a mapping")
    for repo_id, repo in repos.items():
        if repo is None:
            continue
        if not isinstance(repo, dict):
            raise VerificationError(
                f"{path}: repos.{repo_id} must be a mapping or null"
            )
        unknown_repo_fields = set(repo) - REPO_FIELDS
        if unknown_repo_fields:
            raise VerificationError(
                f"{path}: repos.{repo_id} has unsupported fields: "
                f"{', '.join(sorted(unknown_repo_fields))}"
            )
        if "layers" in repo:
            layers = repo["layers"]
            if not isinstance(layers, dict):
                raise VerificationError(
                    f"{path}: repos.{repo_id}.layers must be a mapping"
                )
            for layer_path, value in layers.items():
                if not isinstance(value, (type(None), str, int, bool)):
                    raise VerificationError(
                        f"{path}: repos.{repo_id}.layers.{layer_path} "
                        "must be null, string, integer, or boolean"
                    )


def deep_merge(first: dict[str, Any], later: dict[str, Any]) -> dict[str, Any]:
    merged = dict(first)
    for key, value in later.items():
        if isinstance(merged.get(key), dict) and isinstance(value, dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def resolve_include(repo_root: Path, current_file: Path, include: str) -> Path:
    root_candidate = repo_root / include
    if root_candidate.is_file():
        return root_candidate
    local_candidate = current_file.parent / include
    if local_candidate.is_file():
        return local_candidate
    raise VerificationError(
        f"include not found: {include} "
        f"(tried {root_candidate} and {local_candidate})"
    )


def builtin_config(target: Path, repo_root: Path) -> dict[str, Any]:
    def expand(path: Path, stack: tuple[Path, ...]) -> dict[str, Any]:
        resolved = path.resolve()
        if resolved in stack:
            raise VerificationError(f"include cycle at {path}")
        source = load_yaml(path)
        validate_builtin_schema(source, path)
        combined: dict[str, Any] = {}
        includes = source["header"].get("includes", [])
        for include in includes:
            include_path = resolve_include(repo_root, path, include)
            combined = deep_merge(
                combined, expand(include_path, stack + (resolved,))
            )
        return deep_merge(combined, source)

    return expand(target, ())


def kas_config(target: Path, repo_root: Path) -> dict[str, Any]:
    from kas.includehandler import IncludeHandler

    config, _missing_repos = IncludeHandler(
        [str(target)], str(repo_root), use_lock=False
    ).get_config()
    return config


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise VerificationError(f"cannot read {path}: {exc}") from exc
    for line in lines:
        value = line.strip()
        if not value or value.startswith("#") or "=" not in value:
            continue
        key, content = value.split("=", 1)
        values[key.strip()] = content.strip()
    return values


def check_all_headers(repo_root: Path) -> None:
    for path in sorted((repo_root / "kas").rglob("*.yml")):
        if path.name.endswith(".lock.yml"):
            continue
        config = load_yaml(path)
        header = config.get("header")
        if not isinstance(header, dict) or header.get("version") != 14:
            raise VerificationError(
                f"{path.relative_to(repo_root)}: header.version must be 14"
            )


def verify_target(
    release: str, variant: str, repo_root: Path, engine: str
) -> None:
    target_path = repo_root / "kas" / "targets" / f"{release}-{variant}.yml"
    if not target_path.is_file():
        raise VerificationError(f"target file not found: {target_path}")

    config = (
        builtin_config(target_path, repo_root)
        if engine == "builtin"
        else kas_config(target_path, repo_root)
    )
    check_all_headers(repo_root)

    variant_env = read_env(
        repo_root / "config" / "variants" / f"{variant}.env"
    )
    machine_env = read_env(
        repo_root / "config" / "machines" / "qemux86-64.env"
    )
    release_env = read_env(repo_root / "config" / f"{release}.env")
    if config.get("distro") != variant_env.get("DISTRO"):
        raise VerificationError(
            f"distro {config.get('distro')!r} != {variant_env.get('DISTRO')!r}"
        )
    if config.get("target") != variant_env.get("IMAGE"):
        raise VerificationError(
            f"target {config.get('target')!r} != {variant_env.get('IMAGE')!r}"
        )
    if config.get("machine") != machine_env.get("MACHINE"):
        raise VerificationError(
            f"machine {config.get('machine')!r} != "
            f"{machine_env.get('MACHINE')!r}"
        )

    repos = config.get("repos")
    if not isinstance(repos, dict):
        raise VerificationError("merged repos must be a mapping")
    mode = release_env.get("REPO_MODE")
    expected_repos = (
        {"poky"}
        if mode == "poky"
        else {"openembedded-core", "bitbake", "meta-yocto"}
        if mode == "split"
        else None
    )
    if expected_repos is None:
        raise VerificationError(f"unsupported REPO_MODE: {mode!r}")
    if variant == "custom":
        expected_repos.add("yp")
    if set(repos) != expected_repos:
        raise VerificationError(
            f"repo set {sorted(repos)} != expected {sorted(expected_repos)}"
        )

    for repo_id, tag_env_keys in REPO_ENV_KEYS.items():
        if repo_id not in expected_repos:
            continue
        expected_tag = release_env.get(tag_env_keys[0])
        repo = repos.get(repo_id)
        if not isinstance(repo, dict) or repo.get("tag") != expected_tag:
            actual_tag = repo.get("tag") if isinstance(repo, dict) else None
            raise VerificationError(
                f"repos.{repo_id}.tag {actual_tag!r} != {expected_tag!r}"
            )

    if variant == "custom":
        custom_repo = repos.get("yp")
        if not isinstance(custom_repo, dict):
            raise VerificationError("custom variant requires repo yp")
        layers = custom_repo.get("layers")
        if not isinstance(layers, dict) or set(layers) != {"layers/meta-yp"}:
            raise VerificationError(
                "repos.yp.layers must contain only layers/meta-yp"
            )
        # meta-yp 是本仓库自身，必须以「本地仓库」形态引入：不给 url，
        # 也不给任何版本引用，kas 才会用配置根作 path 且不做 VCS 操作。
        # 一旦写了 url，kas 会去 clone 私有仓库（慢且需要凭证）。
        for forbidden in ("url", "commit", "tag", "branch", "refspec", "path"):
            if custom_repo.get(forbidden) is not None:
                raise VerificationError(
                    f"repos.yp.{forbidden} must be absent: meta-yp is a local "
                    "repository resolved from the configuration root"
                )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--engine", choices=("auto", "kas", "builtin"), default="auto"
    )
    parser.add_argument("--release", choices=RELEASES)
    parser.add_argument("--variant", choices=VARIANTS)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help=(
            "repository root (defaults to the repository containing "
            "this script)"
        ),
    )
    args = parser.parse_args()
    if (args.release is None) != (args.variant is None):
        parser.error("--release and --variant must be specified together")
    return args


def select_engine(requested: str) -> str:
    if requested == "builtin":
        return "builtin"
    try:
        import kas.includehandler
    except ImportError as exc:
        if requested == "kas":
            raise VerificationError(f"kas engine unavailable: {exc}") from exc
        return "builtin"
    return "kas"


def main() -> int:
    args = parse_args()
    repo_root = args.root.resolve()
    try:
        engine = select_engine(args.engine)
    except VerificationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"engine={engine}")

    if args.release:
        selected = [(args.release, args.variant)]
    else:
        selected = [
            (release, variant)
            for release in RELEASES
            for variant in VARIANTS
        ]
    failures = 0
    for release, variant in selected:
        target_name = f"{release}-{variant}"
        try:
            verify_target(release, variant, repo_root, engine)
        except Exception as exc:  # Show parse/schema/IO errors per target.
            failures += 1
            print(f"FAIL {target_name}: {exc}")
    if failures:
        return 1
    print(f"{len(selected)} targets OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
