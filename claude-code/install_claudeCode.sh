#!/bin/bash

currentUser=$(ls -l /dev/console | awk '{ print $3 }')
settings_dir="/Library/Application Support/ClaudeCode"
settings_path="${settings_dir}/managed-settings.json"
settings_url="${4:-https://YOUR_SETTINGS_SOURCE/managed-settings.json}"
node_version="${5:-25.2.1}"
node_url="https://nodejs.org/dist/v${node_version}/node-v${node_version}.pkg"
dialogBinary="/usr/local/bin/dialog"
bar_title="IT Notification"
tertiary_button_cta_payload="Need help? Open a ticket with IT: https://google.com"
options=("Install Claude Code, Uninstall Claude Code")
latest_settings=$(curl -s "$settings_url")
logo="logo.svg"

dialogCheck() {
    # Install SwiftDialog
    if [[ ! -e "$dialogBinary" ]] || [[ ! -e '/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/Dialog' ]]; then
        echo "*************************************************************"
        echo "*****Installing SwiftDialog*****"
        echo "*************************************************************"
        sudo rm -f /tmp/SwiftDialog.pkg
        sleep 2
        sudo /usr/bin/curl -Lo /tmp/SwiftDialog.pkg https://github.com/swiftDialog/swiftDialog/releases/download/v2.5.5/dialog-2.5.5-4802.pkg
        sudo installer -pkg /tmp/SwiftDialog.pkg -target /
    else
        echo "SwiftDialog already installed. Version: $(/usr/local/bin/dialog -v)"
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

action_dialog() {
    local IFS=$'\n'

    # echo "\"${options[@]}\""

    userSelection=($(/bin/launchctl "asuser" "$currentUserUID" sudo -u "$currentUser" $dialogBinary \
    --title "$bar_title" \
    --message "Please select an option. Please note this will install Claude Code via a global npm install." \
    --messagealignment left \
    --icon "$logo" \
    --helpmessage "$tertiary_button_cta_payload" \
    --selecttitle ,radio \
    --selectvalues "$options" \
    --button1text "OK" \
    --button2text "Cancel" \
    --titlefont 'shadow=true, size=25' \
    --messagefont 'size=14' \
    --height '300' \
    --width '650' \
    --position 'center' \
    --moveable \
    --ontop))

    if [[ $? == "2" ]];then
        echo "User cancelled"
        exit 0
    fi

    if [[ ${userSelection[0]} ]];then
        case ${userSelection[0]} in
            *"Install Claude Code"*)
                echo "Installing Claude Code"
                full_install
                ;;
            *"Uninstall Claude Code"*)
                echo "Uninstalling Claude Code"
                full_uninstall
                ;;
            *)
                echo "Invalid selection"
                ;;
        esac
    fi
}

chk_claude() {
    echo "Checking if Claude Code is installed"
    if npm list -g | grep -q @anthropic-ai/claude-code; then
        echo "Claude Code is installed via npm"
        return 0
    elif /bin/launchctl "asuser" "$currentUserUID" sudo -u "$currentUser" which claude; then
        echo "Claude Code is installed (in PATH as user)"
        return 0
    elif which claude > /dev/null 2>&1; then
        echo "Claude Code is installed (in PATH as root)"
        return 0
    elif [[ -e "/opt/homebrew/bin/claude" ]]; then
        echo "Claude Code is installed via Homebrew"
        return 0
    else
        echo "Claude Code is not installed"
        return 1
    fi
}

get_node() {
    if [[ ! $(npm -v) ]] || [[ ! $(node -v) ]]; then
        curl -Lo /tmp/node.pkg ${node_url}
        sudo installer -pkg /tmp/node.pkg -target /
        rm -rf /tmp/node.pkg

        if [[ ! $(npm -v) ]] || [[ ! $(node -v) ]]; then
            echo "Node.js installation failed"
            exit 1
        fi
    else
        echo "Node.js is already installed"
    fi
}

get_claude() {
    if ! chk_claude; then
        echo "Installing Claude Code"
        npm install -g @anthropic-ai/claude-code
        sleep 5
        if ! chk_claude; then
            echo "Error: Claude Code not installed"
            notifyUser "ERROR: Claude Code failed to install"
            exit 1
        fi
    else
        echo "Claude Code is already installed"
    fi
}

deploy_settings() {
    if [[ ! -e "$settings_dir" ]]; then
        echo "Creating settings directory"
        sudo mkdir -p "$settings_dir"
    fi

    if [[ ! -e "$settings_path" ]]; then
        echo "Creating settings file"
        sudo touch "$settings_path"
        echo "Writing settings to file"
        echo "$latest_settings" | sudo tee "$settings_path" > /dev/null
    else
        echo "Settings file already exists"
        if [[ $(cat "$settings_path") == "$latest_settings" ]]; then
            echo "Settings file is up to date"
            return 0
        else
            echo "Settings file is different"
            echo "Updating settings file"
            echo "$latest_settings" | sudo tee "$settings_path" > /dev/null
        fi
    fi
}

uninstall_claude() {
    if chk_claude; then
        echo "Uninstalling Claude Code"
        sudo npm uninstall -g @anthropic-ai/claude-code
        /bin/launchctl "asuser" "$currentUserUID" sudo -u "$currentUser" npm uninstall -g @anthropic-ai/claude-code
        /bin/launchctl "asuser" "$currentUserUID" sudo -u "$currentUser" npm uninstall @anthropic-ai/claude-code
        sleep 5
        if chk_claude; then
            echo "Error: Claude Code not uninstalled"
            notifyUser "ERROR:Claude Code failed to uninstall"
            exit 1
        fi
    else
        echo "Claude Code is not installed"
    fi
}

delete_settings() {
    # if [[ -e "$settings_path" ]]; then
    #     echo "Removing settings file"
    #     sudo rm -f "$settings_path"
    # fi
    
    if [[ -e "$settings_dir" ]]; then
        echo "Removing settings directory"
        sudo rm -rf "$settings_dir"
    fi
}

full_install() {
    get_node
    get_claude
    deploy_settings
    notifyUser "Claude Code installed successfully"
}

full_uninstall() {
    uninstall_claude
    delete_settings
    notifyUser "Claude Code uninstalled successfully"
}

# action_dialog
echo $settings_url
echo $node_version


exit $?