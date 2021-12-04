#!/bin/bash

source _utils.sh

# ------------------------------------------------------------------------------
e_pending "Creating defaults"
# ------------------------------------------------------------------------------

if ! has_command "xcode-select"; then
  e_pending "Installing xcode-select (CLI tools)"
  xcode-select --install
  test_command "xcode-select"
fi

if ! has_command "brew"; then
  e_pending "Installing brew (Homebrew)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  brew doctor
  test_command "brew"
fi
