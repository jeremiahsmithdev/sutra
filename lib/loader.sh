# loader.sh — Source all ralph components.
#
# Centralises the source directives and shellcheck hints so the
# main ralph file stays clean. Order matters: config and utils
# must load before anything that calls log() or reads config vars.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(dirname "$LIB_DIR")/templates"

# shellcheck source=lib/splash.sh
source "$LIB_DIR/splash.sh"
# shellcheck source=lib/config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=lib/utils.sh
source "$LIB_DIR/utils.sh"
# shellcheck source=lib/utils_beads.sh
source "$LIB_DIR/utils_beads.sh"
# shellcheck source=lib/args.sh
source "$LIB_DIR/args.sh"
# shellcheck source=lib/prereqs.sh
source "$LIB_DIR/prereqs.sh"
# shellcheck source=lib/sandbox.sh
source "$LIB_DIR/sandbox.sh"
# shellcheck source=lib/remote.sh
source "$LIB_DIR/remote.sh"
# shellcheck source=lib/monitor.sh
source "$LIB_DIR/monitor.sh"
# shellcheck source=lib/monitor_render.sh
source "$LIB_DIR/monitor_render.sh"
# shellcheck source=lib/tasks.sh
source "$LIB_DIR/tasks.sh"
# shellcheck source=lib/playlist.sh
source "$LIB_DIR/playlist.sh"
# shellcheck source=lib/playlist_validate.sh
source "$LIB_DIR/playlist_validate.sh"
# shellcheck source=lib/prompt_context.sh
source "$LIB_DIR/prompt_context.sh"
# shellcheck source=lib/prompt.sh
source "$LIB_DIR/prompt.sh"
# shellcheck source=lib/format_stream.sh
source "$LIB_DIR/format_stream.sh"
# shellcheck source=lib/invoke.sh
source "$LIB_DIR/invoke.sh"
# shellcheck source=lib/invoke_retry.sh
source "$LIB_DIR/invoke_retry.sh"
# shellcheck source=lib/circuit_breaker.sh
source "$LIB_DIR/circuit_breaker.sh"
# shellcheck source=lib/task_outcome.sh
source "$LIB_DIR/task_outcome.sh"
# shellcheck source=lib/lifecycle.sh
source "$LIB_DIR/lifecycle.sh"
