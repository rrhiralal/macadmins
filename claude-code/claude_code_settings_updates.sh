#!/bin/bash

# Claude Code managed settings updater
#
# Sources the managed-settings.json and CLAUDE.md content for each file independently.
# Each source value may be EITHER a URL (fetched via curl) OR raw inline content:
#   - a value starting with http:// or https:// is fetched from that URL
#   - any other non-empty value is used verbatim as the file's raw content
#
# Jamf script parameters:
#   $4  silent          - "true" (default) suppresses the end-user swiftDialog notification
#   $5  settings source - URL or raw managed-settings.json content (overrides hardcoded/default)
#   $6  CLAUDE.md source - URL or raw CLAUDE.md content (overrides hardcoded/default)
#
# Resolution order per file: parameter -> hardcoded variable -> default URL.
# Because Jamf parameters have practical length limits, raw content (or an alternate URL)
# can instead be hardcoded in the *_source_hardcoded variables below.

currentUser=$(ls -l /dev/console | awk '{ print $3 }')
settings_dir="/Library/Application Support/ClaudeCode"
settings_json_path="${settings_dir}/managed-settings.json"
claude_md_path="${settings_dir}/CLAUDE.md"
settings_json_url="<SETTINGS_JSON_URL>"
claude_md_url="<CLAUDE_MD_URL>"
dialogBinary="/usr/local/bin/dialog"
bar_title="IT Notification"
tertiary_button_cta_payload="Need help? Open a ticket with IT: <IT_SERVICE_DESK_URL>"
silent=${4:-true}
settings_source_param="${5:-}"
claude_md_source_param="${6:-}"
logo="/Library/Scripts/IT/Image assets/logo.svg"

# Optional in-script sources (used when the matching parameter is empty).
# Each may be a URL (fetched) or raw inline content. Leave empty to use the default URLs above.
settings_source_hardcoded=''
claude_md_source_hardcoded=''

dialogCheck() {
    if [[ ! -e "$dialogBinary" ]] || [[ ! -e '/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog' ]]; then
        echo "Dialog binary not found"
        echo "Running policy to install dialog"
        sudo jamf policy -event install-dialog
        sleep 10
    fi
}

logoCheck() {
    if [[ ! -e "$logo" ]]; then
        echo "Icon not found"
        echo "Running policy to install icon"
        sudo jamf policy -event install-images
        sleep 10
    fi
}

notifyUser() {
    /bin/launchctl "asuser" "$currentUserUID" sudo -u "$currentUser" $dialogBinary \
    --title "$bar_title" \
    --message "$1" \
    --messagealignment left \
    --icon "$logo" \
    --helpmessage "$tertiary_button_cta_payload" \
    --button1text "OK" \
    --titlefont 'shadow=true, size=25' \
    --messagefont 'size=14' \
    --height '300' \
    --width '650' \
    --position 'center' \
    --moveable \
    --ontop
}

get_updates() {
    local url="$1"
    local response=$(curl -s -w "\n%{http_code}" "$url")
    local http_code=$(echo "$response" | tail -n1)
    local data=$(echo "$response" | sed '$d')

    # Check HTTP status code
    if [[ "$http_code" != "200" ]]; then
        echo "Failed to fetch data from $url (HTTP $http_code)" >&2
        return 1
    fi

    # Check if data is not empty
    if [[ -z "$data" ]]; then
        echo "Data fetched from $url is empty" >&2
        return 1
    fi

    # Return the data via stdout
    echo "$data"
    return 0
}

validate_json() {
    # Returns 0 if the supplied string is valid JSON, 1 otherwise.
    local data="$1"
    local tmp
    tmp=$(mktemp)
    printf '%s' "$data" > "$tmp"
    # plutil -lint parses as a plist and rejects JSON objects; converting instead
    # exercises plutil's JSON parser and returns non-zero on malformed input.
    if plutil -convert xml1 -o /dev/null "$tmp" > /dev/null 2>&1; then
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

resolve_source() {
    # Resolve a file's content from a source that is either a URL or raw inline content.
    # Args: <label> <source> [validate_json]
    # Emits the resolved content on stdout; diagnostics on stderr. Returns non-zero on failure.
    local label="$1"
    local source="$2"
    local require_json="$3"
    local data

    if [[ "$source" =~ ^https?:// ]]; then
        echo "Fetching $label from URL: $source" >&2
        data=$(get_updates "$source") || return 1
    else
        echo "Using raw inline content for $label" >&2
        data="$source"
    fi

    if [[ -z "$data" ]]; then
        echo "$label content is empty" >&2
        return 1
    fi

    if [[ "$require_json" == "validate_json" ]] && ! validate_json "$data"; then
        echo "$label content is not valid JSON. Refusing to overwrite managed file." >&2
        return 1
    fi

    printf '%s' "$data"
    return 0
}

apply_updates() {
    local name="$1"
    local data="$2"
    local path="$3"

    if [[ -f "$path" ]]; then
        local current_data=$(cat "$path")
        if [[ "$current_data" != "$data" ]]; then
            echo "Data is different"
            echo "Updating data"
            echo "$data" | sudo tee "$path" > /dev/null
            # Return status: 1 = updated
            return 1
        else
            echo "Data is the same, no changes made"
            # Return status: 0 = no change
            return 0
        fi
    else
        echo "Creating file"
        mkdir -p "$settings_dir"
        sudo touch "$path"
        echo "$data" | sudo tee "$path" > /dev/null
        # Return status: 2 = created
        return 2
    fi
}


dialogCheck
logoCheck

# Initialize array to collect update statuses
declare -a update_messages=()

# Resolve each source: parameter -> hardcoded variable -> default URL
settings_source="${settings_source_param:-${settings_source_hardcoded:-$settings_json_url}}"
claude_md_source="${claude_md_source_param:-${claude_md_source_hardcoded:-$claude_md_url}}"

# Resolve settings JSON (validated before it can overwrite the managed file)
echo "Resolving settings JSON..."
latest_settings_json=$(resolve_source "Settings JSON" "$settings_source" "validate_json")
if [[ $? -ne 0 ]]; then
    echo "Failed to resolve settings JSON. Exiting."
    exit 1
fi
echo "Settings JSON resolved successfully"

# Resolve CLAUDE.md (markdown, no JSON validation)
echo "Resolving CLAUDE.md..."
latest_md=$(resolve_source "CLAUDE.md" "$claude_md_source")
if [[ $? -ne 0 ]]; then
    echo "Failed to resolve CLAUDE.md. Exiting."
    exit 1
fi
echo "CLAUDE.md resolved successfully"

# Apply updates using the generic function and collect status
echo "Applying settings JSON updates..."
apply_updates "Settings JSON" "$latest_settings_json" "$settings_json_path"
json_status=$?
case $json_status in
    0)
        update_messages+=("• managed-settings.json: Already up to date \n")
        ;;
    1)
        update_messages+=("• managed-settings.json: Updated successfully \n")
        ;;
    2)
        update_messages+=("• managed-settings.json: Created successfully \n")
        ;;
esac

echo "Applying CLAUDE.md updates..."
apply_updates "CLAUDE.md" "$latest_md" "$claude_md_path"
md_status=$?
case $md_status in
    0)
        update_messages+=("• CLAUDE.md: Already up to date \n")
        ;;
    1)
        update_messages+=("• CLAUDE.md: Updated successfully \n")
        ;;
    2)
        update_messages+=("• CLAUDE.md: Created successfully \n")
        ;;
esac

# Send a single notification with all updates if not in silent mode
if [[ "$silent" == false ]]; then
    # Join array elements with newlines
    notification_message="Claude Code Settings Update:\n\n"
    for msg in "${update_messages[@]}"; do
        notification_message+="$msg\n"
    done
    notifyUser "$notification_message"
fi

echo "Update process completed successfully"
exit 0
