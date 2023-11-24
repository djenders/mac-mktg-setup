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
"arc"
"atom"
"brave-browser"
"copilot"
"cyberduck"
"discord"
"dosbox-x"
"dropbox"
"evernote"
"geekbench"
"google-chrome"
"grammarly-desktop"
"hyper"
"keepassx"
"logi-options-plus"
"logitech-g-hub"
"logitune"
"microsoft-office"
"microsoft-teams"
"private-internet-access"
"rectangle"
"reflector"
"silicon-info"
"slack"
"spotify"
"streamlabs-obs"
"the-unarchiver"
"warp"
"webex-meetings"
"zoom"
)

declare -a app_desc=(
"Adobe Creative Cloud"
"Airy"
"Arc"
"Atom"
"Brave Browser"
"Copilot"
"Cyberduck"
"Discord"
"DOSBox-X"
"Dropbox"
"Evernote"
"Geekbench"
"Google Chrome"
"Grammarly Desktop"
"Hyper"
"KeePassX"
"Logitech Options+"
"Logitech G HUB"
"LogiTune"
"Microsoft Office 365"
"Microsoft Teams"
"Private Internet Access"
"Rectangle"
"Reflector"
"Silicon Info"
"Slack"
"Spotify"
"Streamlabs OBS"
"The Unarchiver"
"Warp"
"Cisco Webex Meetings"
"Zoom"
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
