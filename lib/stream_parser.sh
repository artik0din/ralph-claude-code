#!/bin/bash
# Stream Parser for Claude Code JSON Output
# Parses stream-json output in real-time and displays formatted events

# Colors for different event types
STREAM_COLOR_TOOL='\033[0;36m'      # Cyan for tool calls
STREAM_COLOR_TEXT='\033[0;37m'      # White for text output
STREAM_COLOR_THINK='\033[0;35m'     # Purple for thinking
STREAM_COLOR_ERROR='\033[0;31m'     # Red for errors
STREAM_COLOR_SUCCESS='\033[0;32m'   # Green for success
STREAM_COLOR_FILE='\033[0;33m'      # Yellow for file operations
STREAM_COLOR_RESET='\033[0m'

# Icons for different events
ICON_READ="📖"
ICON_WRITE="📝"
ICON_EDIT="✏️ "
ICON_GREP="🔍"
ICON_GLOB="📂"
ICON_BASH="💻"
ICON_THINK="💭"
ICON_TEXT="💬"
ICON_ERROR="❌"
ICON_SUCCESS="✅"
ICON_TOOL="🔧"

# Stream output file for live monitoring
STREAM_LIVE_FILE=".ralph_stream_live"
STREAM_EVENTS_FILE=".ralph_stream_events"

# Initialize stream parser
init_stream_parser() {
    echo "" > "$STREAM_LIVE_FILE"
    echo "[]" > "$STREAM_EVENTS_FILE"
}

# Get timestamp for log entries
stream_timestamp() {
    date '+%H:%M:%S'
}

# Format and display a tool call event
format_tool_event() {
    local tool_name="$1"
    local tool_params="$2"
    local ts=$(stream_timestamp)
    local icon="$ICON_TOOL"
    local color="$STREAM_COLOR_TOOL"
    local details=""

    case "$tool_name" in
        "Read")
            icon="$ICON_READ"
            color="$STREAM_COLOR_FILE"
            details=$(echo "$tool_params" | jq -r '.file_path // .path // "unknown"' 2>/dev/null | xargs basename 2>/dev/null || echo "file")
            ;;
        "Write")
            icon="$ICON_WRITE"
            color="$STREAM_COLOR_FILE"
            details=$(echo "$tool_params" | jq -r '.file_path // .path // "unknown"' 2>/dev/null | xargs basename 2>/dev/null || echo "file")
            ;;
        "Edit")
            icon="$ICON_EDIT"
            color="$STREAM_COLOR_FILE"
            details=$(echo "$tool_params" | jq -r '.file_path // .path // "unknown"' 2>/dev/null | xargs basename 2>/dev/null || echo "file")
            ;;
        "Grep")
            icon="$ICON_GREP"
            local pattern=$(echo "$tool_params" | jq -r '.pattern // "..."' 2>/dev/null)
            details="\"${pattern:0:30}\""
            ;;
        "Glob")
            icon="$ICON_GLOB"
            local pattern=$(echo "$tool_params" | jq -r '.pattern // "..."' 2>/dev/null)
            details="$pattern"
            ;;
        "Bash")
            icon="$ICON_BASH"
            local cmd=$(echo "$tool_params" | jq -r '.command // "..."' 2>/dev/null)
            details="${cmd:0:40}"
            ;;
        "Task")
            icon="🚀"
            local desc=$(echo "$tool_params" | jq -r '.description // "subagent"' 2>/dev/null)
            details="$desc"
            ;;
        "TodoWrite")
            icon="📋"
            details="updating tasks"
            ;;
        *)
            details="$tool_name"
            ;;
    esac

    echo -e "${color}[$ts] $icon $tool_name: $details${STREAM_COLOR_RESET}"
}

# Format thinking/reasoning output
format_thinking_event() {
    local thinking_text="$1"
    local ts=$(stream_timestamp)

    # Truncate long thinking text
    local truncated="${thinking_text:0:100}"
    if [[ ${#thinking_text} -gt 100 ]]; then
        truncated="${truncated}..."
    fi

    echo -e "${STREAM_COLOR_THINK}[$ts] $ICON_THINK $truncated${STREAM_COLOR_RESET}"
}

# Format text output
format_text_event() {
    local text="$1"
    local ts=$(stream_timestamp)

    # Truncate long text
    local truncated="${text:0:80}"
    if [[ ${#text} -gt 80 ]]; then
        truncated="${truncated}..."
    fi

    # Only show non-empty text
    if [[ -n "${truncated// }" ]]; then
        echo -e "${STREAM_COLOR_TEXT}[$ts] $ICON_TEXT $truncated${STREAM_COLOR_RESET}"
    fi
}

# Format error event
format_error_event() {
    local error_text="$1"
    local ts=$(stream_timestamp)

    echo -e "${STREAM_COLOR_ERROR}[$ts] $ICON_ERROR $error_text${STREAM_COLOR_RESET}"
}

# Format success event
format_success_event() {
    local message="$1"
    local ts=$(stream_timestamp)

    echo -e "${STREAM_COLOR_SUCCESS}[$ts] $ICON_SUCCESS $message${STREAM_COLOR_RESET}"
}

# Parse a single JSON line from Claude's stream output
# Returns formatted output or empty string if not displayable
parse_stream_line() {
    local json_line="$1"

    # Skip empty lines
    if [[ -z "$json_line" ]]; then
        return
    fi

    # Validate JSON
    if ! echo "$json_line" | jq empty 2>/dev/null; then
        return
    fi

    # Extract event type
    local event_type=$(echo "$json_line" | jq -r '.type // empty' 2>/dev/null)

    case "$event_type" in
        "tool_use")
            local tool_name=$(echo "$json_line" | jq -r '.name // .tool // "unknown"' 2>/dev/null)
            local tool_input=$(echo "$json_line" | jq -c '.input // .parameters // {}' 2>/dev/null)
            format_tool_event "$tool_name" "$tool_input"
            ;;
        "content_block_start")
            local content_type=$(echo "$json_line" | jq -r '.content_block.type // empty' 2>/dev/null)
            if [[ "$content_type" == "tool_use" ]]; then
                local tool_name=$(echo "$json_line" | jq -r '.content_block.name // "tool"' 2>/dev/null)
                echo -e "${STREAM_COLOR_TOOL}[$(stream_timestamp)] $ICON_TOOL Starting: $tool_name${STREAM_COLOR_RESET}"
            fi
            ;;
        "content_block_delta")
            local delta_type=$(echo "$json_line" | jq -r '.delta.type // empty' 2>/dev/null)
            case "$delta_type" in
                "text_delta")
                    local text=$(echo "$json_line" | jq -r '.delta.text // empty' 2>/dev/null)
                    # Only show significant text chunks
                    if [[ ${#text} -gt 20 ]]; then
                        format_text_event "$text"
                    fi
                    ;;
                "thinking_delta")
                    local thinking=$(echo "$json_line" | jq -r '.delta.thinking // empty' 2>/dev/null)
                    if [[ ${#thinking} -gt 50 ]]; then
                        format_thinking_event "$thinking"
                    fi
                    ;;
                "input_json_delta")
                    # Tool input being streamed - accumulate but don't display
                    ;;
            esac
            ;;
        "tool_result")
            local is_error=$(echo "$json_line" | jq -r '.is_error // false' 2>/dev/null)
            if [[ "$is_error" == "true" ]]; then
                local error_content=$(echo "$json_line" | jq -r '.content // "Error occurred"' 2>/dev/null)
                format_error_event "${error_content:0:100}"
            fi
            ;;
        "message_stop"|"message_end")
            format_success_event "Response complete"
            ;;
        "error")
            local error_msg=$(echo "$json_line" | jq -r '.error.message // .message // "Unknown error"' 2>/dev/null)
            format_error_event "$error_msg"
            ;;
        # Handle assistant message events
        "assistant")
            local content=$(echo "$json_line" | jq -r '.message.content[0] // empty' 2>/dev/null)
            if [[ -n "$content" ]]; then
                local content_type=$(echo "$content" | jq -r '.type // empty' 2>/dev/null)
                if [[ "$content_type" == "tool_use" ]]; then
                    local tool_name=$(echo "$content" | jq -r '.name // "tool"' 2>/dev/null)
                    local tool_input=$(echo "$content" | jq -c '.input // {}' 2>/dev/null)
                    format_tool_event "$tool_name" "$tool_input"
                fi
            fi
            ;;
    esac
}

# Main stream parser function - reads from stdin and outputs formatted events
# Usage: claude --output-format stream-json ... | stream_parser_main
stream_parser_main() {
    init_stream_parser

    while IFS= read -r line; do
        local formatted=$(parse_stream_line "$line")
        if [[ -n "$formatted" ]]; then
            echo "$formatted"
            echo "$formatted" >> "$STREAM_LIVE_FILE"
        fi
    done
}

# Parse a file containing stream-json output
parse_stream_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "File not found: $file"
        return 1
    fi

    while IFS= read -r line; do
        parse_stream_line "$line"
    done < "$file"
}

# Tail and parse a growing stream file in real-time
tail_and_parse_stream() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "Waiting for stream file: $file"
        while [[ ! -f "$file" ]]; do
            sleep 1
        done
    fi

    tail -f "$file" | while IFS= read -r line; do
        local formatted=$(parse_stream_line "$line")
        if [[ -n "$formatted" ]]; then
            echo "$formatted"
        fi
    done
}

# Export functions for use in other scripts
export -f init_stream_parser
export -f stream_timestamp
export -f format_tool_event
export -f format_thinking_event
export -f format_text_event
export -f format_error_event
export -f format_success_event
export -f parse_stream_line
export -f stream_parser_main
export -f parse_stream_file
export -f tail_and_parse_stream
