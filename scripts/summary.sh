#!/bin/bash

source _utils.sh

# ------------------------------------------------------------------------------
e_message "Creating summary"
# ------------------------------------------------------------------------------

echo "\r"

e_success "$(uname -p) Architecture"
if has_path "Developer"; then
  e_success "~/Developer"
else
  e_failure "~/Developer"
fi
if has_path "Sandbox"; then
  e_success "~/Sandbox"
else
  e_failure "~/Sandbox"
fi

test_command "xcode-select"
test_command "brew"

if has_cask "font-jetbrains-mono-nerd-font"; then
  e_success "JetBrains Mono Nerd Font"
else
  e_failure "JetBrains Mono Nerd Font"
fi

test_app "Adobe Creative Cloud"
test_app "Airy"
test_app "Atom"
test_app "Brave Browser"
test_app "Cyberduck"
test_app "Discord"
test_app "DOSBox-X"
test_app "Dropbox"
test_app "Evernote"
test_app "Google Chrome"
test_app "Hyper"
test_app "KeePassX"
test_app "Microsoft Office 365"
test_app "Microsoft Teams"
test_app "Obsidian"
test_app "Parallels"
test_app "Parallels Toolbox"
test_app "Slack"
test_app "Spotify"
test_app "Streamlabs OBS"
test_app "Cisco Webex Meetings"
test_app "Zoom"

# ------------------------------------------------------------------------------
e_message "Summary complete"
# ------------------------------------------------------------------------------
