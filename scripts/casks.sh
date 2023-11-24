#!/bin/bash

source _utils.sh

# ------------------------------------------------------------------------------
e_pending "Checking applications"
# ------------------------------------------------------------------------------

declare -a cask_name=(
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

declare -a cask_desc=(
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
