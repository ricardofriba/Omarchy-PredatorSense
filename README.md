# PredatorSense for Omarchy — PH315-52 fixes

A fork of [Rezwoan/Omarchy-PredatorSense](https://github.com/Rezwoan/Omarchy-PredatorSense), adding support for the **Acer Predator Helios 300 PH315-52** through the `facer` driver from [cleyton1986/predator-sense](https://github.com/cleyton1986/predator-sense).

## What changed

- Keyboard static colors, brightness and effects use the `facer` character devices.
- Fan Auto / 50% / 70% / Max use firmware WMI controls through hwmon, with mode readback and rollback on failure.
- The panel reads the actual fan mode and percentage instead of a remembered setting.
- Named power presets no longer abort when optional keyboard/profile state files do not exist yet.
- Failed control commands produce a notification; only one control command runs at a time.
- The existing Linuwu-Sense backend remains available on machines that use it. The new facer bridge is deliberately restricted to PH315-52.

Marketplace identity: `io.github.ricardofriba.predatorsense`. Since 1.2.0 this fork uses its own plugin ID, privileged helper, polkit action and state directory. It does not replace Rezwoan's installation. Disable the original widget before using this fork to avoid competing hardware commands:

```bash
omarchy plugin disable io.github.rezwoan.performance
```

Versions 1.1.x of this fork used the original ID; their release tags remain available. Install 1.2.0 as a new plugin and enable its privileged controls once.

## Tested hardware

Acer Predator PH315-52, Intel UHD 630 + NVIDIA GTX 1660 Ti, Arch/Omarchy, Linux `7.1.9-arch1-2`, NVIDIA `610.57.04`.

Observed fan response:

| Setting | CPU fan | GPU fan |
| --- | ---: | ---: |
| Max | 5,880 RPM | 6,240 RPM |
| 70% | 4,500 RPM | 4,980 RPM |
| Auto after Max | 2,880 RPM | 3,360 RPM |

These are measurements from one test, not guaranteed target RPM. Static blue RGB commands completed successfully; visual confirmation is pending. The bridge exposes the five animated effects supported by the reference protocol (Breathing, Neon, Wave, Shifting, Zoom). Battery charge limiting and ACPI thermal profiles are unavailable in this tested configuration.

## Install the plugin

Use this fork's repository URL with Omarchy:

```bash
omarchy plugin add https://github.com/ricardofriba/Omarchy-PredatorSense.git --enable --yes
omarchy restart shell
```

Without anything else the panel is read-only. Hardware controls need the separately installed helper package below.

## Install the privileged helper

The plugin never runs anything as root from its own (user-writable) checkout. Power, CPU, fan, battery and keyboard writes go through a small root-owned, verb-restricted helper that you install yourself as a normal pacman package:

```bash
cd ~/.config/omarchy/plugins/io.github.ricardofriba.predatorsense/packaging/helper
makepkg -si
```

The panel's **Copy install command** button copies exactly that command. Review [`packaging/helper/PKGBUILD`](packaging/helper/PKGBUILD) before running it: it downloads the four privileged files from one pinned commit of this repository and verifies their SHA-256 checksums, so the installed code is the reviewed snapshot even if the plugin checkout later changes. The package installs:

| Path | Purpose |
| --- | --- |
| `/usr/bin/omarchy-predatorsense-ph31552-helper` | Accepts only whitelisted verbs and validated values |
| `/usr/lib/omarchy-predatorsense-ph31552/facer.py` | PH315-52 facer RGB/fan bridge, run by the helper |
| `/usr/share/polkit-1/actions/io.github.ricardofriba.predatorsense.helper.policy` | polkit action scoped to that exact helper path (`auth_admin_keep`) |
| `/usr/lib/systemd/system/omarchy-predatorsense-ph31552-restore.service` | Optional boot restore of the last preset (disabled by default) |

Every hardware change asks for administrator authentication through polkit (remembered for a few minutes). No sudoers file or passwordless rule is installed. To restore the last preset at boot:

```bash
sudo systemctl enable omarchy-predatorsense-ph31552-restore.service
```

Updating the helper means pulling a plugin update and running `makepkg -si` again in the same directory.

### Upgrading from 1.2.0

Version 1.2.0 installed the helper from inside the panel. Remove those files before installing the package (pacman refuses to overwrite the old polkit policy):

```bash
sudo systemctl disable --now omarchy-predatorsense-ph31552-restore.service
sudo rm -f /usr/local/bin/omarchy-predatorsense-ph31552-helper \
  /usr/local/lib/omarchy-predatorsense-ph31552-facer.py \
  /usr/share/polkit-1/actions/io.github.ricardofriba.predatorsense.helper.policy \
  /etc/systemd/system/omarchy-predatorsense-ph31552-restore.service
sudo systemctl daemon-reload
```

## Install the PH315-52 driver

The plugin alone cannot add missing kernel interfaces. The reproducible Arch recipe in [`packaging/facer`](packaging/facer) downloads `facer.c` at pinned commit `61178196ad8d4620ea26379a62c7558817193a9d`, verifies its checksum, and enables the existing WMI PWM implementation specifically for PH315-52.

From a checkout of this repository:

```bash
omarchy pkg add base-devel dkms linux-headers
cd packaging/facer
makepkg -si
```

Use headers matching your installed kernel if you use something other than `linux`. If Linuwu-Sense is installed, remove it before installing this conflicting driver; both claim the same Acer WMI device.

Load the new driver:

```bash
sudo modprobe -r acer_wmi
sudo modprobe facer
```

If loading fails, restore the original driver with `sudo modprobe acer_wmi`. Verify `/dev/acer-gkbbl-0`, `/dev/acer-gkbbl-static-0`, and `pwm1_enable` / `pwm2_enable` under the Acer directory in `/sys/class/hwmon/` before enabling boot persistence:

```bash
printf 'blacklist acer_wmi\nblacklist linuwu_sense\n' | sudo tee /etc/modprobe.d/predatorsense-facer.conf
printf 'facer\n' | sudo tee /etc/modules-load.d/predatorsense-facer.conf
sudo limine-mkinitcpio
omarchy restart shell
```

The final integration does not use `/dev/ec` or load `acpi_ec`. DKMS rebuilds the driver for new kernels; build compatibility with future kernels must be checked during updates.

Optional GPU mode switching uses `envycontrol`:

```bash
omarchy pkg aur add envycontrol
```

Changing GPU mode may require rebooting. It is not required for keyboard or fan controls.

## Remove

Remove the widget and its helper package:

```bash
omarchy plugin remove io.github.ricardofriba.predatorsense
sudo systemctl disable --now omarchy-predatorsense-ph31552-restore.service
sudo pacman -R predatorsense-ph31552-helper
```

Saved settings remain in `/var/lib/omarchy-predatorsense-ph31552`; remove that directory separately if no longer wanted. Driver removal is optional if another app uses facer. If you installed it solely for this plugin, remove the two boot configuration files described above, then remove the package:

```bash
sudo rm -f /etc/modprobe.d/predatorsense-facer.conf /etc/modules-load.d/predatorsense-facer.conf
sudo pacman -R predator-facer-dkms
sudo limine-mkinitcpio
```

Reboot when convenient to return to the stock Acer driver. Remove those configuration files only if you created them for this installation. This does not uninstall the original plugin or its helper.

## Verification

```bash
python3 -m unittest discover -s tests -v
bash -n status.sh system/omarchy-predatorsense-ph31552-helper packaging/facer/PKGBUILD packaging/helper/PKGBUILD
omarchy plugin validate .
```

The tests use temporary files or pure protocol functions and do not write to hardware; they also check that the helper package's pinned checksums match the files in `system/`. Hardware validation additionally checked WMI mode readback and RPM changes. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for Omarchy reload and UI validation.

## Credits and licensing

- Original Omarchy plugin: Rezwoan, [MIT](LICENSE).
- Hardware protocol/reference driver: [cleyton1986/predator-sense](https://github.com/cleyton1986/predator-sense) and its contributors; based on JafarAkhondali's Acer RGB driver.
- The externally downloaded kernel source retains its own GPL license. This repository's MIT license does not relicense that driver.
- Acer/Predator trademarks are covered by the original [notice](NOTICE.md).
