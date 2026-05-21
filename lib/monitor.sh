# monitor.sh — Live dashboard entry point and run loop.
#
# Polls .sutra/state and beads every second via render_dashboard()
# (defined in monitor_render.sh). Launched via `sutra --monitor` in a
# separate terminal.

run_remote_monitor() {
    # shellcheck source=/dev/null
    source .sutra_remote

    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_DIR" ]]; then
        log "ERROR: Invalid .sutra_remote file"
        return 1
    fi

    sync_sutra
    log "Monitoring remote sutra on ${C_BOLD_CYAN}${REMOTE_HOST}:${REMOTE_DIR}${C_RESET}"
    ssh -t "$REMOTE_HOST" "cd '$REMOTE_DIR' && ~/.sutra/sutra --monitor"
}

run_monitor() {
    if [[ -f ".sutra_remote" ]]; then
        run_remote_monitor
        return $?
    fi

    if [[ ! -d ".beads" ]]; then
        log "ERROR: No .beads/ in $(pwd). Run from a beads-enabled project."
        exit 1
    fi

    init_dashboard_terminal
    while true; do
        render_dashboard
        sleep 1
    done
}

# Initial terminal setup: clear, hide cursor, install exit trap.
init_dashboard_terminal() {
    printf '\033[2J\033[H\033[?25h'
    printf '\033[?25l'
    trap 'printf "\033[?25h\033[J"; exit 0' INT
}
