# CLAUDE.md

tuios versions a TTY kiosk setup for a MacBook Pro 11,1 on a barebone Arch Linux
(until 2026-11 Fedora 44, then named tuios-fedora; that state is in the git history):
the firmware boots a UKI, tty1 autologin starts sway with `foot --server`, every window
is a tab in swaybar, and one dependency-free C program, `swaybar-status`, draws the bar
(tabs plus status). Everything else is config files mirroring the real paths under
`home/` (= `~`) and `system/` (= `/`), plus `packages.txt` (`pacman -Qqe`). `SETUP.md`
is the reproduction guide; nothing deploys automatically.

## Commands

```sh
make CFLAGS='-O2 -Wall -Wextra -Werror' all   # what CI builds, with gcc and clang
make test                                     # unit tests in tests/
make clean && make test CFLAGS='-O2 -Wall -Wextra -Werror -g -fsanitize=address,undefined -fno-sanitize-recover=all'
make install          # swaybar-status -> ~/.local/bin, then swaymsg reload
```

- CI (`.github/workflows/ci.yml`): job `c` builds and tests with gcc and clang, then
  again under ASan/UBSan; job `shell` runs shellcheck on an explicit file list. A new shell script must be added to that
  list, or CI will not check it. `.shellcheckrc` disables SC1090/SC1091 (sourced files
  exist only on the target machine).
- Battery path can be overridden at build time: `-DBATDIR=\"/sys/class/power_supply/BAT1/\"`.

## Architecture

- `src/swaybar-status.c`: swaybar's `status_command` (`--loop 5`). In loop mode it also
  holds sway IPC connections and manages tabs: one window per workspace, workspaces
  renamed `N:<title>` (bar strips the number). Key bindings in the sway config talk to it
  through `swaymsg -t send_tick <word>` (`next`, `prev`, `split`, `volume`). Output is
  Pango markup; it writes a line only when the output changed. The Claude weekly limit
  appears while `$XDG_RUNTIME_DIR/claude-bar/limits` exists (its writer
  `claude-usage` is not part of the Arch setup yet; inotify triggers a redraw).
  `--cols N` makes the tab labels share the bar width left free by the status.
  All icons go through `sym()` with one `ICON_SPAN`; the bar font must be the
  proportional Nerd Font variant (`CaskaydiaMono NFP`), or icons overlap the digits.
- `tests/*.c` `#include` the program source (with `main` renamed) to reach static
  helpers; `tests/check.h` is a tiny counted-assertion harness. No test framework.
- `home/bash_profile`: tty1 starts sway; the sway config opens Claude Code in the first terminal.
- `system/usr/local/sbin/auto-update.sh` (daily timer) and `system/usr/local/bin/craft-update`
  (signature-checked Craft app updates) are the only scripts outside the C program.

## Conventions

- Code, comments and docs in English; user-facing strings (unit descriptions,
  script output) in German.
- C: no dependencies beyond libc and kernel headers; the bar avoids stdio streams on
  purpose (open/read/write, own number formatter). Keep it fork-free per tick: the only
  fork is `wpctl get-volume`, run at start and on the `volume` tick.
- Barebone: add a package or a tuning step only when it is missing in practice or
  measured to help; SETUP.md records what was measured and left out.
- Colours are Catppuccin Mocha; glyphs need a Nerd Font.

## Rules and pitfalls

- The live machine runs copies of `home/` and `system/` files, not symlinks into this
  repo; nothing installs them except `make install` for the bar. A config change here must also be applied at the live path (and vice versa).
  The live copies may carry German comments; never copy them over the repo files wholesale.
- Handle each key in exactly one place (the sway config). On Fedora a key daemon plus
  sway bindings fired two actions per press.
- swaybar keeps the old `status_command` running after a binary update; only
  `swaymsg reload` restarts it (`make install` does that).
- Never kill the bar by pattern (`pkill -f`, `kill $(pgrep -f ...)`): the
  pattern also matches the calling shell's command line, which then dies too. Use
  `pkill -x swaybar-status`.
- The WLAN interface (`wlp3s0`) and battery (`BAT0`) are fixed in the source; the WLAN
  signal comes from the nl80211 scan cache because the `wl` driver refuses
  `GET_STATION` to non-root.
- Public repo: never add WLAN names, addresses, serials, router or account details to
  configs or docs.

## Workflow

- Every change starts with a GitHub issue. Branch `<issue>-<slug>` from `main`,
  open a PR with `Closes #<issue>`. Never push to `main` directly.
- PRs auto-merge (squash) once CI and the "Linked ticket" check pass; drafts are not merged.
- Versions exist only as git tags `vX.Y.Z`. Every merge to `main` tags the next patch;
  never edit version numbers in files. Minor/major releases: Actions -> Release.
- Nothing deploys automatically: install on the machine with `make install` and by
  copying changed files from `home/` and `system/`.
- Measure power only while Claude Code is idle (background job after the turn): its
  spinner redraws the screen and distorts the reading by ~4 W.
- Never `modprobe -r wl` on the live machine: wpa_supplicant loses the interface
  until reboot.
- Details: CONTRIBUTING.md.
