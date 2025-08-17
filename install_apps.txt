#!/bin/bash
set -euo pipefail

echo "=== Preparing Environment ==="
export DEBIAN_FRONTEND=noninteractive

# Determine the real desktop user (works whether or not you used sudo)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
echo "Target user for NVM/Node: $TARGET_USER ($TARGET_HOME)"

echo "=== Updating and Upgrading Ubuntu ==="
sudo apt update && sudo apt -y upgrade

echo "=== Installing Required Dependencies ==="
sudo apt install -y wget curl gnupg lsb-release apt-transport-https software-properties-common ca-certificates flatpak gnome-shell-extension-prefs build-essential

# Ensure Flathub is enabled for Flatpak
if ! flatpak remote-list | grep -q flathub; then
    echo "=== Adding Flathub repository ==="
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

#############################################
# Google Chrome
#############################################
echo "=== Adding Google Chrome Repo ==="
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | \
    sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null

#############################################
# Spotify
#############################################
echo "=== Adding Spotify Repo ==="
curl -sS https://download.spotify.com/debian/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/spotify.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/spotify.gpg] http://repository.spotify.com stable non-free" | \
    sudo tee /etc/apt/sources.list.d/spotify.list >/dev/null

#############################################
# Visual Studio Code
#############################################
echo "=== Adding VS Code Repo ==="
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null

#############################################
# Update Sources
#############################################
echo "=== Updating Package Sources ==="
sudo apt update

#############################################
# Install Applications (APT)
#############################################
echo "=== Installing Applications ==="
# virtualbox-ext-pack can be interactive; allow failure to avoid blocking
sudo apt install -y \
    google-chrome-stable \
    spotify-client \
    vlc \
    code \
    htop \
    timeshift \
    virtualbox virtualbox-ext-pack || true
sudo apt install -y tmux

#############################################
# WhatsApp Desktop (Flathub)
#############################################
echo "=== Installing WhatsApp Desktop ==="
flatpak install -y flathub com.github.eneshecan.WhatsAppForLinux

#############################################
# Signal (Flathub)
#############################################
echo "=== Installing Signal ==="
flatpak install -y flathub org.signal.Signal

#############################################
# nvm + Node.js (Latest nvm + Latest LTS and Current)
#############################################
echo "=== Installing NVM for $TARGET_USER ==="
su - "$TARGET_USER" -c '
  set -e
  export NVM_DIR="$HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    echo "Downloading and running nvm installer (latest stable)..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
  else
    echo "NVM already present at $NVM_DIR"
  fi

  # Ensure nvm is available in this non-login shell
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

  echo "Installing Node.js Latest LTS..."
  nvm install --lts

  echo "Installing Node.js Latest Current..."
  nvm install node

  echo "Setting default Node.js to LTS..."
  nvm alias default lts/*

  echo "Enabling Corepack (Yarn/PNPM shims)..."
  corepack enable || true

  echo "Node versions installed:"
  nvm ls
  node -v
  npm -v
'

# Make sure user shells always load nvm (idempotent)
echo "=== Wiring NVM into $TARGET_USER shell profiles ==="
NVM_SNIPPET='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'

for RC in ".bashrc" ".zshrc" ".profile"; do
  RC_PATH="$TARGET_HOME/$RC"
  if [ -f "$RC_PATH" ]; then
    if ! grep -q 'export NVM_DIR="$HOME/.nvm"' "$RC_PATH"; then
      echo "$NVM_SNIPPET" | sudo tee -a "$RC_PATH" >/dev/null
    fi
  else
    echo "$NVM_SNIPPET" | sudo tee "$RC_PATH" >/dev/null
  fi
done
sudo chown "$TARGET_USER":"$TARGET_USER" "$TARGET_HOME"/.bashrc "$TARGET_HOME"/.zshrc "$TARGET_HOME"/.profile 2>/dev/null || true

#############################################
# Ensure Desktop Entries (for APT apps if missing)
#############################################
echo "=== Ensuring .desktop launchers exist for APT apps ==="

# Chrome
cat <<EOF | sudo tee /usr/share/applications/google-chrome.desktop >/dev/null
[Desktop Entry]
Version=1.0
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable %U
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
EOF

# Spotify
cat <<EOF | sudo tee /usr/share/applications/spotify.desktop >/dev/null
[Desktop Entry]
Name=Spotify
GenericName=Music Player
Exec=spotify %U
Terminal=false
Type=Application
Icon=spotify-client
Categories=Audio;Music;Player;AudioVideo;
EOF

# VS Code
cat <<EOF | sudo tee /usr/share/applications/code.desktop >/dev/null
[Desktop Entry]
Name=Visual Studio Code
Exec=/usr/bin/code --no-sandbox --unity-launch %F
Icon=code
Type=Application
StartupNotify=true
Categories=Utility;TextEditor;Development;IDE;
EOF

#############################################
# Pin Apps to Dock (append without removing existing ones)
#############################################
echo "=== Pinning apps to GNOME Dock (keeping existing favorites) ==="
# Run gsettings as the desktop user (not root)
CURRENT_FAVORITES=$(sudo -u "$TARGET_USER" gsettings get org.gnome.shell favorite-apps || echo "[]")
FAVORITES=$(echo "$CURRENT_FAVORITES" | sed "s/^\['//;s/'\]$//;s/', '/ /g")

NEW_APPS=("google-chrome.desktop" "spotify.desktop" "code.desktop" "com.github.eneshecan.WhatsAppForLinux.desktop" "org.signal.Signal.desktop")

for APP in "${NEW_APPS[@]}"; do
    if [[ ! " $FAVORITES " =~ " $APP " ]]; then
        FAVORITES="$FAVORITES $APP"
    fi
done

UPDATED_FAVORITES=$(printf "'%s', " $FAVORITES)
UPDATED_FAVORITES="[${UPDATED_FAVORITES%, }]"
sudo -u "$TARGET_USER" gsettings set org.gnome.shell favorite-apps "$UPDATED_FAVORITES" || true

#############################################
# Install all global NPM packages
#############################################

npm i -g axios react lodash chalk async colors eslint dotenv socket.io react-redux path mongodb bootstrap jess sass-loader postcss jsonwebtoken cors react-router browserify prettier nodemailer nodemon ts-lint sqlite3

#############################################
# Maintenance & Cleanup
#############################################
echo "=== Running Maintenance & Cleanup ==="
sudo apt -y autoremove
sudo apt -y autoclean
sudo apt -y clean
sudo snap refresh
flatpak update -y || true



echo "=== All Done! 🚀 ==="

