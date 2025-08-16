#!/bin/bash

echo "=== Updating and Upgrading Ubuntu ==="
sudo apt update && sudo apt -y upgrade

echo "=== Installing Required Dependencies ==="
sudo apt install -y wget curl gnupg lsb-release apt-transport-https software-properties-common ca-certificates flatpak gnome-shell-extension-prefs

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
    sudo tee /etc/apt/sources.list.d/google-chrome.list

#############################################
# Spotify
#############################################
echo "=== Adding Spotify Repo ==="
curl -sS https://download.spotify.com/debian/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/spotify.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/spotify.gpg] http://repository.spotify.com stable non-free" | \
    sudo tee /etc/apt/sources.list.d/spotify.list

#############################################
# Visual Studio Code
#############################################
echo "=== Adding VS Code Repo ==="
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
    sudo tee /etc/apt/sources.list.d/vscode.list

#############################################
# Update Sources
#############################################
echo "=== Updating Package Sources ==="
sudo apt update

#############################################
# Install Applications (APT)
#############################################
echo "=== Installing Applications ==="
sudo apt install -y \
    google-chrome-stable \
    spotify-client \
    vlc \
    code \
    htop \
    timeshift \
    virtualbox virtualbox-ext-pack \
    tmux

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
# Ensure Desktop Entries (for APT apps if missing)
#############################################
echo "=== Ensuring .desktop launchers exist for APT apps ==="

# Chrome
cat <<EOF | sudo tee /usr/share/applications/google-chrome.desktop
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
cat <<EOF | sudo tee /usr/share/applications/spotify.desktop
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
cat <<EOF | sudo tee /usr/share/applications/code.desktop
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

# Get current favorites
CURRENT_FAVORITES=$(gsettings get org.gnome.shell favorite-apps)

# Convert to array
FAVORITES=$(echo $CURRENT_FAVORITES | sed "s/^\['//;s/'\]$//;s/', '/ /g")

# Apps we want to add
NEW_APPS=("google-chrome.desktop" "spotify.desktop" "code.desktop" "com.github.eneshecan.WhatsAppForLinux.desktop" "org.signal.Signal.desktop")

# Append missing ones
for APP in "${NEW_APPS[@]}"; do
    if [[ ! " $FAVORITES " =~ " $APP " ]]; then
        FAVORITES="$FAVORITES $APP"
    fi
done

# Convert back to gsettings format
UPDATED_FAVORITES=$(printf "'%s', " $FAVORITES)
UPDATED_FAVORITES="[${UPDATED_FAVORITES%, }]"

# Apply updated favorites
gsettings set org.gnome.shell favorite-apps "$UPDATED_FAVORITES"

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
echo "=== Please restart your system to apply all changes. ==="