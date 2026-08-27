# Contributing

Thanks for considering a contribution. This plugin is intentionally small and
single-purpose — please keep changes in that spirit.

## Reporting a bug

Open a [GitHub issue](../../issues/new/choose) using the **Bug report** template.
Please include:

- Your laptop model and CPU (Predator model + CPU family, if not this one)
- Output of `omarchy-shell shell ping` (confirms the shell is responding)
- Any relevant lines from `journalctl --user -t omarchy-shell | grep -i rezwoan`
- What you clicked and what happened instead of what you expected

## Requesting a feature

Open an issue with the **Feature request** template. If it's specific to a
different Acer/Predator model or a different Intel/AMD platform, say so —
sysfs paths and ACPI hotkey behavior vary enough between vendors that
"works on mine" isn't safe to assume elsewhere.

## Contributing code

1. Fork the repo, make your change.
2. Test it for real: `omarchy plugin add <your-fork-url> --enable`, then
   `omarchy restart shell` after every edit — hot-reload does **not**
   reliably pick up changes to a widget already sitting in the bar (see the
   note in `README.md`). Confirm with a fresh quickshell PID, not just the
   "Local plugin changed, reloading" journal line.
3. Validate before opening a PR:
   ```bash
   omarchy plugin validate .
   /usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Panel.qml   # not on PATH by default
   bash -n setup.sh enable-keyboard.sh status.sh
   ```
4. If you touch `setup.sh`'s privileged helper, keep every verb an explicit
   whitelist match (`case ... in known-value) ...; *) exit 2 ;; esac`) — never
   pass user/QML input straight into a shell command. This is what keeps a
   passwordless-feeling `pkexec` action safe to ship.
5. Open a PR describing what you tested and on what hardware.

## Project layout

| File | Purpose |
|---|---|
| `manifest.json` | Plugin declaration |
| `Panel.qml` | Bar icon + popup panel (all UI) |
| `Model.js` | Pure JS: JSON parsing, label/icon lookups — no QML types |
| `status.sh` | Read-only status snapshot (sysfs/systemctl reads, no privilege) |
| `setup.sh` | One-time privileged setup, run via the panel's own button (`pkexec`) |
| `enable-keyboard.sh` | One-time `acer_wmi` → `linuwu_sense` module swap, same button pattern |
| `assets/predator-mask.png` | Recolorable logo (white silhouette, alpha background) |

See `README.md`'s "How it works" section for the polkit-based privilege model
before changing anything that touches `/usr/local/bin/omarchy-perf-helper`.
