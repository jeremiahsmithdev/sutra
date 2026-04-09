if .type == "assistant" then
    (.message.content[]? |
        if .type == "text" then "TEXT: " + (.text | .[0:200])
        elif .type == "tool_use" then "TOOL: " + .name + " " + (.input | to_entries | map(.key + "=" + (.value | tostring | .[0:80])) | join(", "))
        else empty end)
elif .type == "result" then
    "RESULT: " + (.result // "no result") + " (turns: " + (.num_turns | tostring) + ")"
elif .type == "error" then
    "ERROR: " + (.error.message // .error // "unknown error")
else empty end