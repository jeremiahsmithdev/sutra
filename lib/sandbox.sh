# sandbox.sh — Bubblewrap sandbox support for Claude invocations.
#
# When SANDBOX_MODE=true, builds a bwrap argument array that makes
# the entire filesystem read-only except the project directory,
# ~/.claude (session state), and /tmp.

init_sandbox() {
    BWRAP_ARGS=()

    if [[ "$SANDBOX_MODE" != "true" ]]; then
        return
    fi

    log "Sandbox mode: Claude will be jailed to $PWD"

    BWRAP_ARGS=(
        --ro-bind / /
        --bind "$PWD" "$PWD"
        --bind "$HOME/.claude" "$HOME/.claude"
        --tmpfs /tmp
        --dev /dev
        --proc /proc
        --die-with-parent
    )
}
