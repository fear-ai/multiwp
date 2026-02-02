#!/bin/bash
# cmd.sh - Shared helpers for launching commands with consistent output handling.

: "${COMMON_LOADED:?${BASH_SOURCE[0]##*/} requires common.sh to be sourced first.}"

CMD_LOADED=1

cmd_mode_file_count() {
    case "${1-}" in
        inherit) echo 0 ;;
        out|err|merge|out-append|err-append|merge-append) echo 1 ;;
        both|both-append) echo 2 ;;
        *) return 1 ;;
    esac
}

cmd_join() {
    local out=""
    local arg
    for arg in "$@"; do
        out+="${arg} "
    done
    echo "${out% }"
}

cmd_require_mode() {
    local mode="${1-}"
    if ! cmd_mode_file_count "$mode" >/dev/null 2>&1; then
        err "Unsupported cmd mode: ${mode}"
    fi
}

cmd_parse() {
    local label="${1-}"
    local mode="${2-}"
    shift 2 || true

    [ -n "$label" ] || err "cmd label is required"
    cmd_require_mode "$mode"

    local out_file=""
    local err_file=""

    case "$mode" in
        inherit) ;;
        out|out-append)
            out_file="${1-}"
            shift || true
            ;;
        err|err-append)
            err_file="${1-}"
            shift || true
            ;;
        both|both-append)
            out_file="${1-}"
            err_file="${2-}"
            shift 2 || true
            ;;
        merge|merge-append)
            out_file="${1-}"
            shift || true
            ;;
    esac

    [ "${1-}" = "--" ] || err "cmd ${label}: missing -- separator"
    shift || true

    [ "$#" -gt 0 ] || err "cmd ${label}: missing command"

    CMD_LABEL="$label"
    CMD_MODE="$mode"
    CMD_OUT_FILE="$out_file"
    CMD_ERR_FILE="$err_file"
    CMD_ARGS=("$@")
}

run_cmd() {
    cmd_parse "$@"

    case "$CMD_MODE" in
        inherit)
            "${CMD_ARGS[@]}"
            ;;
        out)
            "${CMD_ARGS[@]}" > "$CMD_OUT_FILE"
            ;;
        out-append)
            "${CMD_ARGS[@]}" >> "$CMD_OUT_FILE"
            ;;
        err)
            "${CMD_ARGS[@]}" 2> "$CMD_ERR_FILE"
            ;;
        err-append)
            "${CMD_ARGS[@]}" 2>> "$CMD_ERR_FILE"
            ;;
        both)
            "${CMD_ARGS[@]}" > "$CMD_OUT_FILE" 2> "$CMD_ERR_FILE"
            ;;
        both-append)
            "${CMD_ARGS[@]}" >> "$CMD_OUT_FILE" 2>> "$CMD_ERR_FILE"
            ;;
        merge)
            "${CMD_ARGS[@]}" > "$CMD_OUT_FILE" 2>&1
            ;;
        merge-append)
            "${CMD_ARGS[@]}" >> "$CMD_OUT_FILE" 2>&1
            ;;
    esac
}

start_cmd() {
    cmd_parse "$@"
    local pid=""

    case "$CMD_MODE" in
        inherit)
            "${CMD_ARGS[@]}" &
            pid=$!
            ;;
        out)
            "${CMD_ARGS[@]}" > "$CMD_OUT_FILE" &
            pid=$!
            ;;
        out-append)
            "${CMD_ARGS[@]}" >> "$CMD_OUT_FILE" &
            pid=$!
            ;;
        err)
            "${CMD_ARGS[@]}" 2> "$CMD_ERR_FILE" &
            pid=$!
            ;;
        err-append)
            "${CMD_ARGS[@]}" 2>> "$CMD_ERR_FILE" &
            pid=$!
            ;;
        both)
            "${CMD_ARGS[@]}" > "$CMD_OUT_FILE" 2> "$CMD_ERR_FILE" &
            pid=$!
            ;;
        both-append)
            "${CMD_ARGS[@]}" >> "$CMD_OUT_FILE" 2>> "$CMD_ERR_FILE" &
            pid=$!
            ;;
        merge)
            "${CMD_ARGS[@]}" > "$CMD_OUT_FILE" 2>&1 &
            pid=$!
            ;;
        merge-append)
            "${CMD_ARGS[@]}" >> "$CMD_OUT_FILE" 2>&1 &
            pid=$!
            ;;
    esac

    echo "$pid"
}
