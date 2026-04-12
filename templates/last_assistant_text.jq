[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""
