# Claude Code Management

This directory contains scripts for deploying, configuring, and managing [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/overview) — Anthropic's agentic coding tool — on macOS.

## Scripts

### `install_claudeCode.sh`

A comprehensive installation script that handles the entire lifecycle of the Claude Code tool.

**Features:**
- Checks for and installs Node.js if it is missing.
- Installs or uninstalls the `@anthropic-ai/claude-code` npm package globally.
- Deploys a managed configuration file (`managed-settings.json`) from a remote source.
- Uses `swiftDialog` to provide a user interface for selecting "Install" or "Uninstall".
- Checks for `dialog` and attempts to install it via Jamf policy if missing.

**Usage:**
This script is typically run via a management tool (like Jamf Pro) or manually with root privileges. It accepts arguments for the settings URL and Node version.

### `claude_code_settings_updates_clean.sh`

A lightweight script designed to keep the Claude Code configuration in sync.

**Features:**
- Fetches the latest configuration JSON from a specified URL.
- Compares it with the local configuration at `/Library/Application Support/ClaudeCode/managed-settings.json`.
- Updates the local file if changes are detected.
- Notifies the user via `swiftDialog` (can be silenced with a flag).

## Dependencies

- **SwiftDialog**: Used for user notifications and interaction.
- **Node.js**: Required for running Claude Code (installed by the install script if missing).
