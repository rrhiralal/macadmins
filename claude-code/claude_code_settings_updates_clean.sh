#!/bin/bash

currentUser=$(ls -l /dev/console | awk '{ print $3 }')
settings_dir="/Library/Application Support/ClaudeCode"
settings_path="${settings_dir}/managed-settings.json"
config_url="https://YOUR_SETTINGS_SOURCE/managed-settings.json"
dialogBinary="/usr/local/bin/dialog"
bar_title="IT Notification"
tertiary_button_cta_payload="Need help? Open a ticket with IT: https://google.com"
silent=${4:-true}
logo="logo.svg"

dialogCheck() {
    if [[ ! -e "$dialogBinary" ]]; then
        echo "Dialog binary not found"
        echo "Running policy to install dialog"
        sudo jamf policy -event install-dialog
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

# Fetch the latest config from the remote URL
latest_config=$(curl -s "$config_url")

# Read the current config from local file (if it exists)
if [[ -f "$settings_path" ]]; then
    current_config=$(cat "$settings_path")
else
    echo "Creating settings file"
    mkdir -p "$settings_dir"
    sudo touch "$settings_path"
    echo "$latest_config" | sudo tee "$settings_path" > /dev/null
    if [[ "$silent" == false ]]; then
        notifyUser "Config has been created"
    fi
    exit $?
fi

if [[ "$latest_config" != "$current_config" ]]; then
    echo "Config is different"
    echo "Updating config"
    echo "$latest_config" | sudo tee "$settings_path" > /dev/null
    if [[ "$silent" == false ]]; then
        notifyUser "Config has been updated"
    fi
else
    echo "Config is the same"
    if [[ "$silent" == false ]]; then
        notifyUser "Config is already up to date"
    fi
fi

exit $?