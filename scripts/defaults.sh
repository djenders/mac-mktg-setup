#!/bin/bash

source _utils.sh

# ------------------------------------------------------------------------------
e_pending "Creating defaults"
# ------------------------------------------------------------------------------

if ! has_path "Developer"; then
  get_consent "Create ~/Developer folder"
  if has_consent; then
    e_pending "Creating ~/Developer folder"
    mkdir -p ~/Developer
    test_path "Developer"
  fi
fi

if ! has_path "Sandbox"; then
  get_consent "Create ~/Sandbox folder"
  if has_consent; then
    e_pending "Creating ~/Sandbox folder"
    mkdir -p ~/Sandbox
    test_path "Sandbox"
  fi
fi

if ! has_command "xcode-select"; then
  e_pending "Installing xcode-select (CLI tools)"
  xcode-select --install
  test_command "xcode-select"
fi

if ! has_command "brew"; then
  e_pending "Installing brew (Homebrew)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if has_arm; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"'>>$HOME/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  brew doctor
  brew tap homebrew/cask-fonts
  test_command "brew"
fi

# ------------------------------------------------------------------------------
e_message "Defaults complete"
# ------------------------------------------------------------------------------
