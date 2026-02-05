# format_stream.sh — Filter stream-json into human-readable output.
#
# Reads Claude's stream-json JSONL on stdin, prints coloured readable
# lines to stdout. Used by invoke_claude() via process substitution.

format_stream() {
    jq --unbuffered -r '
        def cyan:    "\u001b[36m";
        def green:   "\u001b[32m";
        def yellow:  "\u001b[33m";
        def dim:     "\u001b[2m";
        def bold:    "\u001b[1m";
        def reset:   "\u001b[0m";

        if .type == "assistant" then
            (.message.content[]? |
                if .type == "text" then .text
                elif .type == "tool_use" then
                    "  " + cyan + bold + "▶ " + .name + reset + dim + "  " + (
                        if .name == "Bash" then (.input.command // "")
                        elif .name == "Write" then (.input.file_path // "")
                        elif .name == "Read" then (.input.file_path // "")
                        elif .name == "Edit" then (.input.file_path // "")
                        elif .name == "Glob" then (.input.pattern // "")
                        elif .name == "Grep" then (.input.pattern // "")
                        else (.input | to_entries | map(.value | tostring) | first // "")
                        end) + reset
                else empty end)
        elif .type == "result" then
            "  " + green + bold + "✓ Done" + reset + dim + " (" + (.num_turns | tostring) + " turns, $" + (.total_cost_usd | tostring | .[0:6]) + ")" + reset
        else empty end
    ' 2>/dev/null
}
