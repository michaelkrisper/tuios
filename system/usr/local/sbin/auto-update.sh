#!/bin/bash
# Daily updates (auto-update.timer). Log: journalctl -u auto-update
# Reboots stay manual; a kernel update leaves /run/reboot-needed.
set -u
U=michi
as_user() { runuser -u "$U" -- env HOME=/home/$U "$@"; }
step() { echo "== $*"; }

step pacman
pacman -Syu --noconfirm
pacman -Sc --noconfirm >/dev/null          # keep only packages that are installed

step "AUR google-chrome"
A=/home/$U/.cache/arch-setup/aur/google-chrome
if [ -d "$A" ]; then
    as_user git -C "$A" pull -q --ff-only
    new=$(as_user bash -c "cd '$A' && source PKGBUILD && echo \$pkgver-\$pkgrel")
    cur=$(pacman -Q google-chrome 2>/dev/null | awk '{print $2}')
    if [ "$new" != "$cur" ]; then
        as_user bash -c "cd '$A' && makepkg -f --noconfirm -c" && pacman -U --noconfirm "$A"/google-chrome-"$new"-x86_64.pkg.tar.zst
        rm -f "$A"/*.pkg.tar.zst "$A"/*.deb
    else echo "aktuell ($cur)"; fi
fi

step "Craft-Apps"
as_user /usr/local/bin/craft-update

step "Python (uv, /opt/python)"
UV_PYTHON_INSTALL_DIR=/opt/python UV_PYTHON_BIN_DIR=/usr/local/bin uv python upgrade --preview 2>&1 | tail -3

step rustup
as_user rustup update 2>&1 | tail -3

step "Android-SDK"
as_user /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --update 2>&1 | grep -vE 'deprecated|Android CLI|d.android.com|android sdk|^\s*$' | tail -3


if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    echo "Kernel aktualisiert -> Neustart noetig"; touch /run/reboot-needed
fi
