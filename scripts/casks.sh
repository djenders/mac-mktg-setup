#!/bin/bash

source _utils.sh

# ------------------------------------------------------------------------------
e_message "Checking applications/casks"
# ------------------------------------------------------------------------------

declare -a cask_name=(
"font-jetbrains-mono-nerd-font"
)

declare -a cask_desc=(
"JetBrains Mono Nerd Font"
)

declare -a app_name=(
"adobe-creative-cloud"
"airy"
"chatgpt"
"claude"
"cyberduck"
"discord"
"dropbox"
"evernote"
"geekbench"
"grammarly-desktop"
"ledger-live"
"lm-studio"
"microsoft-office"
"microsoft-teams"
"obsidian"
"private-internet-access"
"rectangle"
"sonos"
"spotify"
"the-unarchiver"
"warp"
)

declare -a app_desc=(
"Adobe Creative Cloud"
"Airy"
"ChatGPT"
"Claude"
"Cyberduck"
"Discord"
"Dropbox"
"Evernote"
"Geekbench"
"Grammarly Desktop"
"Ledger Live"
"LM Studio"
"Microsoft Office 365"
"Microsoft Teams"
"Obsidian"
"Private Internet Access"
"Rectangle"
"Sonos"
"Spotify"
"The Unarchiver"
"Warp"
)

if has_command "brew"; then
  for i in "${!cask_name[@]}"; do
    DESC=${cask_desc[$i]}
    NAME=${cask_name[$i]}
    test_cask "$DESC"
    if ! has_cask "$DESC"; then
      get_consent "Install $DESC"
      if has_consent; then
        e_pending "Installing $NAME"
        brew install --cask $NAME
        test_cask "$DESC"
      fi
    fi
  done
  for i in "${!app_name[@]}"; do
    DESC=${app_desc[$i]}
    NAME=${app_name[$i]}
    test_app "$DESC"
    if ! has_app "$DESC"; then
      get_consent "Install $DESC.app"
      if has_consent; then
        e_pending "Installing $NAME"
        brew install --cask $NAME
        test_app "$DESC"
      fi
    fi
  done
fi

# ------------------------------------------------------------------------------
e_message "Applications/Casks complete"
# ------------------------------------------------------------------------------
