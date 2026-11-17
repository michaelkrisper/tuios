# tuios

[![CI](https://github.com/michaelkrisper/tuios/actions/workflows/ci.yml/badge.svg)](https://github.com/michaelkrisper/tuios/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/michaelkrisper/tuios?sort=semver&label=version)](https://github.com/michaelkrisper/tuios/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Language: C](https://img.shields.io/badge/language-C-555.svg)](src/)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-rolling-1793d1.svg)](SETUP.md)

Versioned TTY kiosk for a MacBook Pro 11,1 on Arch Linux: barebone base, sway
tabs, `foot --server`, Claude Code in the first terminal, and one
dependency-free C program for the bar.

The machine boots a unified kernel image straight from the firmware (no boot
loader), logs in on tty1 and starts sway, whose first window runs Claude Code.
Every window gets its own sway workspace, and the workspace buttons in swaybar
act as tabs that share the bar's width next to the status line. Networking is
`wpa_supplicant` plus `systemd-networkd`; there is no desktop, no
NetworkManager, no audio and no display manager. About 350 packages, idle draw
around 5.2 W at low brightness.

Until 2026-11 this repo was `tuios-fedora` and described the same kiosk on
Fedora 44; that state lives on in the git history (last Fedora commit
`d013be3`).

```
 53%  ↓0.0 ↑12.4 󰁹78% 1:35h  6W  12:41
```

## What is in here

| | |
|---|---|
| `src/swaybar-status.c` | the one bar: tabs (one window per workspace, named after its title, sharing the free width with `--cols`), optional Claude weekly limit, CPU, RAM, network, battery, WLAN, clock — dependency-free C |
| `home/config/sway/config` | bar with tabs + status, foot server, touchpad, brightness keys |
| `home/bash_profile` | tty1 autostart: `exec sway` |
| `system/etc/` | kernel command line, mkinitcpio (UKI), networkd + wpa_supplicant, autologin, udev, auto-update timer |
| `system/usr/local/` | `auto-update.sh` (pacman, AUR Chrome, Craft apps, Python, Rust, Android SDK) and `craft-update` |
| `packages.txt` | explicitly installed packages (`pacman -Qqe`) |
| `home/`, `system/` | every other config the machine runs, mirroring `~` and `/` |

[`SETUP.md`](SETUP.md) documents how to reproduce the whole thing.

## Build

```sh
make && make install          # -> ~/.local/bin, then swaymsg reload
```

`make install` also runs `swaymsg reload`: swaybar keeps the old binary running
and only restarts `status_command` on reload.

## The status line

In `--loop` mode the program also holds two sway IPC connections: every new
window on an occupied workspace moves to a fresh one behind the last, every
workspace is renamed "N:<window title>" (the bar strips the number), and
closing the last window of the visible workspace jumps to the previous tab.
The window title is the working directory (bash `PROMPT_COMMAND`). The Claude
weekly limit appears only while `$XDG_RUNTIME_DIR/claude-bar/limits` exists;
inotify on that directory redraws immediately. The writer for that file
(`claude-usage`, a user timer) lived here in the Fedora days and is not part of
the Arch setup yet.

With `--cols N` (N = bar width in text columns) the tabs share whatever the
status leaves free: every tab label is cut or centre-padded to the same width,
so the buttons fill the bar. Without it labels are cut at 28 characters.

* **CPU** — busy percentage over the last interval, from `/proc/stat`. Turns
  red at 70 %.
* **RAM** — share in use, `MemTotal - MemAvailable` from `/proc/meminfo`, so
  reclaimable page cache counts as free. Turns red at 90 %.
* **Network** — average throughput over the last interval in decimal Mbit/s,
  from `/proc/net/dev`. Loopback and virtual interfaces (`veth*`, `docker*`,
  `podman*`, `br-*`, …) are skipped so bridged traffic is not counted twice.
* **Battery** — charge, remaining time and current draw from
  `/sys/class/power_supply/BAT0`. Remaining time uses a weighted average of the
  last twelve power samples, so it follows load changes without jumping every
  tick. Batteries exposed through the SBS driver report `charge_*`/`current_*`
  in µAh/µA instead of `energy_*`/`power_*` in µWh/µW; both are handled.
* **WLAN** — one to four bars, crossed out when not connected, from nl80211's
  scan cache over netlink. No fork and no root, but the signal is only as fresh
  as the last scan: this kernel has no `/proc/net/wireless`, and the `wl` driver
  answers `GET_STATION` with EPERM unless root. The interface name (`wlp3s0`) is
  fixed in the source.
* **Volume** — speaker with zero to three waves from `wpctl get-volume`, run
  only at start and on sway's `volume` tick. The Arch setup has no audio, so
  `wpctl` is missing and the field stays hidden.

Colours are [Catppuccin Mocha](https://github.com/catppuccin/catppuccin).

Output is Pango markup (`pango_markup enabled` in the bar block).

`--loop [seconds]` is the intended mode: swaybar starts `status_command` once and reads
lines from it for as long as the process lives, which avoids a fork/exec per
tick — at roughly 1 ms that was by far the largest cost. The program exits by
itself via SIGPIPE once swaybar closes the read end, and only writes a line when
the rendered output actually changed, so an idle bar causes no redraws at all.

Without `--loop` it prints one line and keeps its counters in
`$XDG_RUNTIME_DIR/.swaybar-cpu`, which is useful for testing. The battery path can
be overridden at build time:

```sh
make CFLAGS='-O2 -DBATDIR=\"/sys/class/power_supply/BAT1/\"'
```

## Notes

Code, comments and documentation are in English; the few user-facing strings
(systemd unit descriptions, script output) are German, the machine's UI
language.

The glyphs (, 󰁹, 󰂄) come from a Nerd Font. Use the proportional variant
(`CaskaydiaMono NFP`) for the bar: in the plain `NF` variant the icons are wider
than their advance and overlap the digits. All icons share one span
(`ICON_SPAN`: 12pt, rise -2pt) that centres them on the digits.

## Development

The bar is dependency-free C and builds on Linux with gcc or clang:

```sh
make CFLAGS='-O2 -Wall -Wextra -Werror'   # what CI builds with (gcc and clang)
make test                                  # unit tests in tests/
shellcheck home/bash_profile ...           # shell scripts, see .github/workflows/ci.yml
```

The tests include the program sources directly, so they can reach the static
helpers (formatting, the sway JSON parser and tree walk) without changing the programs.

CI tags every merge to `main` with the next patch version; bundled releases
with release notes come from the Release workflow. Changes go through issues
and pull requests, see [CONTRIBUTING](CONTRIBUTING.md).

## License

[MIT](LICENSE)
