# Setup

How to reproduce the kiosk on a MacBook Pro 11,1 (13", late 2013: i5-4258U,
8 GB, Iris 5100, BCM4360 WLAN). The goal is a barebone Arch: start with almost
nothing and add only what turns out to be missing. Files under `system/` and
`home/` are copies of the live files at `/` and `~`; nothing installs them
automatically.

Placeholders in angle brackets (`<SSID>`, `<IP>`, `<Router-IP>`, the PSK) stand
for local values that do not belong in a public repo.

## 1. Disk and base system

One btrfs partition holds everything. Arch lives in its own subvolumes, so it
can be installed next to another system on the same partition and booted
without touching it:

```sh
mount -o subvolid=5 /dev/sda3 /mnt/top
btrfs subvolume create /mnt/top/arch
btrfs subvolume create /mnt/top/arch-home
btrfs property set /mnt/top/arch compression none       # no compression, no snapshots
btrfs property set /mnt/top/arch-home compression none
```

The property is needed because a compress mount option of another system on
the same filesystem would otherwise apply to these subvolumes too.

The base can be installed from any running Linux with the official bootstrap
tarball (verify `archlinux-bootstrap-x86_64.tar.zst.sig` with the release key
first), then `arch-chroot` into it and `pacstrap` into the mounted subvolume.
The first install was:

```sh
pacstrap -K /mnt base linux linux-headers intel-ucode broadcom-wl-dkms \
    wpa_supplicant sudo terminus-font git sway foot ttf-cascadia-mono-nerd ttf-dejavu
```

Arch has no prebuilt `broadcom-wl` any more, so the `wl` driver comes as DKMS,
which pulls in the kernel headers and gcc. `iwd` does not work with `wl`.
`packages.txt` has the full current list (`pacman -Qqe`); `google-chrome` and
the `ai.storyteller.*` packages are not in the repos (sections 7 and 8).

Then, inside the new system: `system/etc/fstab`, `hostname`, `locale.conf`
(plus `locale-gen`), `vconsole.conf` (Terminus 32 for the Retina console,
`mac-de-latin1`), timezone, user `michi` in `wheel`, a sudoers drop-in and
`passwd -l root`.

## 2. Boot without a boot loader

mkinitcpio builds a unified kernel image directly onto the EFI partition, and
the firmware starts it:

- `system/etc/mkinitcpio.d/linux.preset`: only the `default` preset, written
  as `/efi/EFI/arch/linux.efi`.
- `system/etc/kernel/cmdline`: root subvolume plus the power options carried
  over from Fedora (`mem_sleep_default=deep`, `pcie_aspm.policy=powersave`,
  PSR/FBC, `thunderbolt.hosts_only=1`, `acpi_osi=!Darwin`).
- `system/etc/mkinitcpio.conf`: the default hooks without `fsck`. btrfs has
  no fsck helper, and with the hook mkinitcpio ends every build with "errors
  were encountered".

```sh
mkinitcpio -P
efibootmgr -c -d /dev/sda -p 1 -L Arch -l '\EFI\arch\linux.efi'
```

Holding Alt at power-on brings up the Mac boot picker if something goes wrong.

## 3. Network

`wpa_supplicant@wlp3s0` associates, `systemd-networkd` configures, and
`systemd-resolved` resolves (`/etc/resolv.conf` -> `stub-resolv.conf`):

- `system/etc/wpa_supplicant/wpa_supplicant-wlp3s0.conf`: `update_config=1`,
  control socket for `wheel`, so new networks can be added with `wpa_cli`.
  The home network is limited to 2.4 GHz (`freq_list`/`scan_freq`): its 5 GHz
  band is too weak at the desk, and after every resume the attempt ran into a
  10 s authentication timeout before falling back (reconnect 17.5 s -> 3.3 s).
- `system/etc/systemd/network/20-wlan-home.network`: static address for the
  home SSID (reserved at the router), `IgnoreCarrierLoss=yes`, so the address
  survives suspend and no DHCP round trip follows the resume.
- `system/etc/systemd/network/25-wlan.network`: DHCP for every other SSID.

```sh
systemctl enable systemd-networkd systemd-resolved systemd-timesyncd wpa_supplicant@wlp3s0
```

Never `modprobe -r wl` to test something: `wpa_supplicant` keeps running with a
stale nl80211 handle and every scan fails until reboot (or
`systemctl restart wpa_supplicant@wlp3s0`).

## 4. Session

- `system/etc/systemd/system/getty@tty1.service.d/autologin.conf`: autologin.
- `home/bash_profile`: on tty1 `exec sway`, unless `~/.no-sway` exists.
- `home/config/sway/config`: `foot --server`, first window runs Claude Code,
  every window a tab. Brightness keys go through `brightnessctl` (works
  without root via logind): F1/F2 display, F5/F6 keyboard. `hid_apple`
  defaults to `fnmode=3`, so they work without Fn.
- `home/config/foot/foot.ini`, `home/bashrc`, `home/config/starship.toml`.

The bar:

```sh
make && make install
```

and in the sway config
`status_command ~/.local/bin/swaybar-status --loop 5 --cols 160` with the bar
font `CaskaydiaMono NFP 10`. 160 columns is the 1280 px logical width of the
panel at scale 2.

## 5. Power

Measured on battery, display at 14 %, keyboard light at 10 %, Claude Code idle
at its prompt, average of `power_now` over 60 s:

| state | draw |
|---|---|
| barebone, untuned | 5.8 W |
| + WLAN power save | 5.2 W |

What was measured and left out:

- Runtime PM `auto` for all PCI devices and SATA: 5.85 / 5.80 / 5.79 W
  (off/on/off), no effect.
- The package never reaches C7-C10, with or without the above; the panel has
  no PSR. Brightness is the remaining lever.
- `mbpfan`: the SMC firmware runs the fan at ~1300 rpm at idle and ramps it
  under load by itself.

Kept: `system/etc/udev/rules.d/81-wlan-powersave.rules` (power save survives
suspend, tested) and `system/etc/modprobe.d/no-audio.conf` (no audio at all).
The FaceTime camera has no driver on Arch, so it is off as well.

Measuring pitfall: while Claude Code runs a tool its spinner redraws ~13 times
a second and the draw rises to ~9.4 W (package C6 29 % instead of 91 %). Measure
idle draw only from a background job that starts after the turn has ended.

## 6. Development

- Node and npm from the repos. Do not run `npm update -g`: it replaces
  pacman's npm files.
- Rust via `rustup`; `home/cargo/config.toml` trades a little speed for much
  faster local builds: debug info reduced, release without LTO and with 16
  codegen units and incremental builds (a rebuild after a change 0.4 s instead
  of 19 s on ttycast; sudoku solvers 0-2 % slower, binaries ~23 % larger).
  `cargo build --profile release-full` restores full optimisation for
  benchmarks.
- Python: the repos lag behind, so the newest CPython comes from `uv` into
  `/opt/python` with links in `/usr/local/bin` (ahead of `/usr/bin` in PATH;
  pacman's python stays untouched):

  ```sh
  UV_PYTHON_INSTALL_DIR=/opt/python UV_PYTHON_BIN_DIR=/usr/local/bin \
      uv python install 3.15 --default --preview
  ```

- Java: `jdk-openjdk` (newest release).
- Android SDK in `/opt/android-sdk`, owned by the user so `sdkmanager` and AGP
  can install into it without root; `system/etc/profile.d/android.sh` sets
  `ANDROID_HOME`. Older projects point `sdk.dir` at `~/Android/Sdk`, which is a
  symlink to it. Start from the command-line tools zip (checksum from
  `repository2-3.xml`), then `sdkmanager --licenses` and install
  `platform-tools`, the newest `platforms;android-*`, `build-tools` and `ndk`;
  Gradle fetches anything else a project needs. Rust on Android additionally
  needs `rustup target add aarch64-linux-android` and `cargo install cargo-ndk`.

## 7. Browser

Google Chrome rather than Chromium, so the profile and Google sync carry over.
It comes from the AUR PKGBUILD, which only repackages Google's own .deb:

```sh
git clone https://aur.archlinux.org/google-chrome.git && cd google-chrome
makepkg -si
```

## 8. Craft apps

WordCraft, GridCraft, DeckCraft, PhotoCraft, VectorCraft and PdfCraft publish
Arch packages in their GitHub releases (`storytold/<app>`). `craft-update`
installs newer ones after checking the signature of `SHA256SUMS.txt` against
the fixed ArtCraft key and the checksum of the package. Without XWayland
installed they all run as native Wayland clients.

`home/config/mimeapps.list` makes them the default for their file types (PDF
-> PdfCraft, raster images -> PhotoCraft, SVG -> VectorCraft) and Chrome the
default for web links.

## 9. Updates

Arch has no official counterpart to Debian's `unattended-upgrades` and
recommends updating by hand. This machine updates itself anyway:
`auto-update.timer` (daily 12:00, catches up after sleep) runs
`/usr/local/sbin/auto-update.sh`: `pacman -Syu`, the AUR Chrome package,
`craft-update`, `uv python upgrade`, `rustup update` and `sdkmanager --update`.
Reboots stay manual; after a kernel update the script creates
`/run/reboot-needed`. Log: `journalctl -u auto-update`.

```sh
systemctl enable --now auto-update.timer
```
