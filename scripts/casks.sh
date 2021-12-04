#!/bin/bash

source _utils.sh

# ------------------------------------------------------------------------------
e_pending "Checking applications"
# ------------------------------------------------------------------------------

declare -a cask_name=(
"adobe-creative-cloud"
"airy"
"atom"
"brave-browser"
"cyberduck"
"discord"
"dosbox-x"
"dropbox"
"evernote"
"google-chrome"
"hyper"
"keepassx"
"microsoft-office"
"microsoft-teams"
"obsidian"
"parallels"
"parallels-toolbox"
"slack"
"spotify"
"streamlabs-obs"
"webex-meetings"
"zoom"
)

declare -a cask_desc=(
"Adobe Creative Cloud"
"Airy"
"Atom"
"Brave Browser"
"Cyberduck"
"Discord"
"DOSBox-X"
"Dropbox"
"Evernote"
"Google Chrome"
"Hyper"
"KeePassX"
"Microsoft Office 365"
"Microsoft Teams"
"Obsidian"
"Parallels"
"Parallels Toolbox"
"Slack"
"Spotify"
"Streamlabs OBS"
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
