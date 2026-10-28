#!/usr/bin/env bash

_log() {
    local level="$1" color="$2"
    shift 2

    if [[ -t 2 && -z "${NO_COLOR+x}" ]]; then
        printf '\033[%sm[%s]\033[0m %s\n' "${color}" "${level}" "$*" >&2
    else
        printf '[%s] %s\n' "${level}" "$*" >&2
    fi
}

log_info() {
    _log INFO 32 "$@"
}

log_warn() {
    _log WARN 33 "$@"
}

log_error() {
    _log ERROR 31 "$@"
}

die() {
    log_error "$@"
    exit 1
}
