import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// PredatorSense control center for the Acer Predator laptop: a single power
// profile selector, CPU/GPU/fan/battery controls, and keyboard-RGB. Ported
// from an old walker-menu extension (omarchy/extensions/menu.sh) into a
// proper bar-widget plugin for the omarchy-shell era.
//
// Privileged writes go through /usr/bin/omarchy-predatorsense-ph31552-helper, a
// root-owned, verb-whitelisted script authorized via a polkit action scoped
// to that exact binary — no sudoers file, no passwordless-sudo rule. Both are
// installed by the predatorsense-ph31552-helper pacman package (see
// packaging/helper and README.md); the plugin itself never elevates anything
// from its own user-writable checkout. Every control here degrades gracefully when that
// helper — or the optional envycontrol / linuwu-sense-dkms backends — isn't
// installed: read-only status still shows, writes just no-op.
Panel {
  id: root
  moduleName: "io.github.ricardofriba.predatorsense"
  ipcTarget: "io.github.ricardofriba.predatorsense"

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.ricardofriba.predatorsense"
  readonly property string helperPath: "/usr/bin/omarchy-predatorsense-ph31552-helper"
  property var status: Model.parseStatus("")
  property string activeTab: "general"
  property bool showAdvanced: false

  // Bare hex (no #) for the active mode's color — named power preset wins
  // when one is active (it's the deliberate, one-tap choice); otherwise
  // fall back to the power-profile. Empty string means neither maps to a
  // color (fully "custom"): callers each pick their own fallback for that.
  function modeHex() {
    var key = root.status.preset || root.status.profile
    switch (key) {
      case "ultra": case "saver": case "power-saver": return "33ff77"      // green — battery saver
      case "performance": case "ultra-performance": return "ff00ea"         // neon magenta — performance
      case "balanced": return "3b82f6"                                     // blue — balanced
      default: return ""
    }
  }

  // Predator-logo tint: theme foreground is the fallback when modeHex() is
  // empty, so the logo still reflects something even in "custom" state.
  function modeColor() {
    var hex = root.modeHex()
    return hex ? ("#" + hex) : (root.bar ? root.bar.foreground : Color.foreground)
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  // Fire-and-forget a privileged verb through the helper, then refresh once
  // the write has had time to land. `bar.run` is the shared fire-and-forget
  // exec every bar widget uses. pkexec matches the helper's exact path
  // against the polkit action shipped in the helper package, so this prompts
  // via the normal graphical auth dialog (once per auth_admin_keep window, not
  // per click) rather than needing a passwordless-sudo rule. Until the package
  // is installed there is no helper to run, so writes are skipped and the
  // setup banner explains how to install it.
  function runPrivileged() {
    if (!root.status.helperOk) return
    var args = Array.prototype.slice.call(arguments)
    var quoted = args.map(function(a) { return Util.shellQuote(String(a)) })
    runPlain("pkexec " + Util.shellQuote(root.helperPath) + " " + quoted.join(" "))
    refreshTimer.restart()
  }

  function runPlain(cmd) {
    if (actionProc.running) return
    actionProc.command = ["bash", "-c", cmd]
    actionProc.running = true
  }

  // The helper is installed by the user from a terminal as a normal pacman
  // package (its PKGBUILD pins the reviewed files to an exact commit and
  // checksums). The panel only copies the command — it never runs anything
  // as root on the user's behalf.
  readonly property string helperInstallCommand: "cd " + Util.shellQuote(root.pluginDir + "/packaging/helper") + " && makepkg -si"

  function copySetupCommand() {
    root.bar.run("printf '%s' " + Util.shellQuote(root.helperInstallCommand) + " | wl-copy"
      + " && omarchy-notification-send -u low " + Util.shellQuote("PredatorSense")
      + " " + Util.shellQuote("Install command copied — paste it into a terminal"))
  }

  function runEnableKeyboard() { runPrivileged("linuwu-enable") }

  function setPreset(name) {
    runPrivileged("profile", name, root.status.themeHex)
  }

  function setPowerProfile(name) {
    runPlain("powerprofilesctl set " + Util.shellQuote(name)
      + (root.status.helperOk
        ? " && pkexec " + Util.shellQuote(root.helperPath) + " turbo " + (name === "power-saver" ? "off" : "on")
        : ""))
  }

  function setThermal(name) { runPrivileged("platform-profile", name) }
  function toggleTurbo() { runPrivileged("turbo", root.status.turbo === "on" ? "off" : "on") }
  function setCores(name) { runPrivileged("cpu-cores", name) }
  function setCpuCap(pct) { runPrivileged("cpu-cap", pct) }

  function setPowerLimit(pl1) {
    var pl2 = pl1 >= 65 ? 157 : Math.round(pl1 * 1.35)
    runPrivileged("power-limit", pl1, pl2)
  }

  function setGpuMode(mode) {
    if (mode === root.status.gpu) return
    runPlain("pkexec envycontrol -s " + Util.shellQuote(mode)
      + " && omarchy-notification-send -u low " + Util.shellQuote("GPU Mode")
      + " " + Util.shellQuote("Switched to " + mode + " — reboot required"))
  }

  function toggleGpuBoost() { runPrivileged("nvidia-powerd", root.status.powerd === "active" ? "off" : "on") }
  function toggleBatteryLimit() { runPrivileged("battery-limit", root.status.battlimit === "on" ? "off" : "on") }
  function setFan(mode) { runPrivileged("fan", mode) }
  function setKbBrightness(pct) { runPrivileged("kb-bright", pct) }
  function setKbColor(hex) { runPrivileged("kb-zone", hex, "100") }
  function setKbEffect(mode) { runPrivileged("kb-effect", mode, "5", "100", "1", root.status.themeHex) }
  // Stateful, unlike a one-shot color pick: while linked, the keyboard color
  // is re-applied by the helper on every future profile change too (see
  // the helper's kb-link verb). Picking any plain color swatch or effect
  // clears this server-side, which is why those don't need a matching
  // client-side call here. Clicking an already-active link button toggles
  // it back off.
  function setKbLink(mode) {
    if (root.status.kbLink === mode) {
      runPrivileged("kb-link", "off")
    } else {
      runPrivileged("kb-link", mode, root.status.themeHex)
    }
  }

  function openLiveGpuStats() {
    root.bar.run("uwsm-app -- xdg-terminal-exec watch -n1 nvidia-smi")
  }

  function sendBatteryInfo() {
    root.bar.run("bash -c 'info=$(upower -i \"$(upower -e 2>/dev/null | grep -m1 BAT)\" 2>/dev/null | grep -E \"state|percentage|energy-rate|time to|capacity:\" | sed \"s/^ *//\"); omarchy-notification-send -u low \"Battery\" \"${info:-No battery info available}\"'")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: if (opened) refresh()

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    interval: 450
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(code, status) {
      root.refresh()
      if (code !== 0) {
        root.bar.run("notify-send -u normal PredatorSense " + Util.shellQuote(
          actionError.text.trim() || "Command failed or authentication was cancelled"))
      }
    }
  }

  Process {
    id: statusProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.ricardofriba.predatorsense/status.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = Model.parseStatus(text)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: predatorLogoComponent
    tooltipText: root.status.preset ? Model.presetLabel(root.status.preset) : "PredatorSense"
    onPressed: function(b) { root.toggle() }
  }

  // Predator claw mark, recolored per active mode via MultiEffect
  // (colorization tints the mask's opaque pixels; alpha comes from the PNG).
  Component {
    id: predatorLogoComponent
    Item {
      anchors.fill: parent
      Image {
        id: predatorGlyph
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("assets/predator-mask.png")
        visible: false
        layer.enabled: true
      }
      MultiEffect {
        anchors.fill: predatorGlyph
        source: predatorGlyph
        colorization: 1.0
        colorizationColor: root.modeColor()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.height, heroLabels.implicitHeight, heroActions.implicitHeight)

            Item {
              id: heroIcon
              width: Style.font.display
              height: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Image {
                id: heroGlyph
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: Qt.resolvedUrl("assets/predator-mask.png")
                visible: false
                layer.enabled: true
              }
              MultiEffect {
                anchors.fill: heroGlyph
                source: heroGlyph
                colorization: 1.0
                colorizationColor: root.modeColor()
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "PredatorSense"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.status.preset ? Model.presetLabel(root.status.preset) : "CUSTOM"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: heroActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "󰋚"
                tooltipText: "Live GPU stats"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.openLiveGpuStats()
              }
              PanelActionButton {
                iconText: "󰁹"
                tooltipText: "Battery info"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.sendBatteryInfo()
              }
              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "Advanced: power & thermal profile"
                foreground: root.showAdvanced ? Color.accent : root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.showAdvanced = !root.showAdvanced
              }
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.refresh()
              }
            }
          }

          // ---------- Tabs ----------
          ButtonGroup {
            width: parent.width
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            value: root.activeTab
            options: [
              { value: "general", label: "General" },
              { value: "keyboard", label: "Keyboard" }
            ]
            onChanged: function(v) { root.activeTab = v }
          }

          // ---------- Setup banner ----------
          BorderSurface {
            visible: !root.status.helperOk
            width: parent.width
            implicitHeight: setupColumn.implicitHeight + Style.space(16)
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14), 1)

            Column {
              id: setupColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(8)

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Power/CPU/fan/battery/keyboard controls are read-only until the privileged helper package is installed. Copy the command below, paste it into a terminal, and review the package before pacman asks for your password. See the README for details."
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Button {
                text: "Copy install command"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: root.copySetupCommand()
              }
            }
          }

          // ==================== General tab ====================
          Column {
            id: generalTab
            visible: root.activeTab === "general"
            width: parent.width
            spacing: Style.space(14)

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Profile ----------
          // One unified selector replaces the old separate power-preset /
          // power-profile / thermal-profile rows (they all fought over the
          // same "how hard should this laptop run" question). CUSTOM isn't
          // a real preset — it's a passive indicator, shown selected
          // whenever a raw control below (or in the Advanced popover) has
          // been changed since the last named preset was applied.
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Grid {
              id: profileGrid
              readonly property var options: [
                { value: "ultra", label: "Ultra Saver" },
                { value: "saver", label: "Saver" },
                { value: "balanced", label: "Balanced" },
                { value: "performance", label: "Performance" },
                { value: "ultra-performance", label: "Ultra Performance" },
                { value: "custom", label: "Custom" }
              ]
              width: parent.width
              columns: 3
              columnSpacing: Style.spacing.xs
              rowSpacing: Style.spacing.xs

              Repeater {
                model: profileGrid.options
                Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  enabled: modelData.value !== "custom"
                  selected: modelData.value === "custom"
                    ? !root.status.preset
                    : root.status.preset === modelData.value
                  onClicked: root.setPreset(modelData.value)
                }
              }
            }
          }

          // ---------- Advanced (power profile + thermal profile) ----------
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.showAdvanced

            PanelSeparator { foreground: root.bar.foreground }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "POWER PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                value: root.status.profile
                options: [
                  { value: "power-saver", label: "Saver" },
                  { value: "balanced", label: "Balanced" },
                  { value: "performance", label: "Performance" }
                ]
                onChanged: function(v) { root.setPowerProfile(v) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: thermalGroup.options.length > 0

              PanelSectionHeader { text: "THERMAL PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

              // A fixed 3-column Grid rather than ButtonGroup (which is a
              // single non-wrapping Row) — this machine's platform_profile
              // exposes 5 choices, too many to fit one row at readable width.
              Grid {
                id: thermalGroup
                readonly property var options: Model.thermalOptions(root.status.thermalChoices)
                width: parent.width
                columns: 3
                columnSpacing: Style.spacing.xs
                rowSpacing: Style.spacing.xs

                Repeater {
                  model: thermalGroup.options
                  Button {
                    required property var modelData
                    text: modelData.label
                    fontSize: Style.font.bodySmall
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    horizontalPadding: Style.spacing.sm
                    verticalPadding: Style.spacing.controlPaddingY
                    bordered: true
                    selected: root.status.thermal === modelData.value
                    onClicked: root.setThermal(modelData.value)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- CPU ----------
          Column {
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader { text: "CPU"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Toggle {
              width: parent.width
              label: "Turbo boost"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.turbo === "on"
              onClicked: root.toggleTurbo()
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                text: "CORES"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: root.status.cores
                options: [
                  { value: "all", label: "All" },
                  { value: "no-smt", label: "No hyperthreading" },
                  { value: "ecore", label: "E-cores only" }
                ]
                onChanged: function(v) { root.setCores(v) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                text: "MAX FREQUENCY"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: String(root.status.cpucap)
                options: [
                  { value: "100", label: "100%" },
                  { value: "75", label: "75%" },
                  { value: "50", label: "50%" },
                  { value: "40", label: "40%" }
                ]
                onChanged: function(v) { root.setCpuCap(parseInt(v, 10)) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                text: "POWER LIMIT"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: String(root.status.powerlimit)
                options: [
                  { value: "65", label: "Full (65W)" },
                  { value: "45", label: "45W" },
                  { value: "35", label: "35W" },
                  { value: "25", label: "25W" }
                ]
                onChanged: function(v) { root.setPowerLimit(parseInt(v, 10)) }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- GPU ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "GPU"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              visible: root.status.gpuAvailable

              Text {
                text: "MODE · REBOOT REQUIRED"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: root.status.gpu
                options: [
                  { value: "integrated", label: "Integrated" },
                  { value: "hybrid", label: "Hybrid" },
                  { value: "nvidia", label: "Nvidia" }
                ]
                onChanged: function(v) { root.setGpuMode(v) }
              }
            }

            Text {
              visible: !root.status.gpuAvailable
              width: parent.width
              wrapMode: Text.WordWrap
              text: "GPU-mode switching needs envycontrol (AUR) — not installed."
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Toggle {
              width: parent.width
              label: "Dynamic boost"
              description: "nvidia-powerd — lets the dGPU draw more power under load"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.powerd === "active"
              onClicked: root.toggleGpuBoost()
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Battery ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(battHeader.implicitHeight, battValue.implicitHeight)
              PanelSectionHeader {
                id: battHeader
                text: "BATTERY"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: battValue
                text: (root.status.battpct || "—") + "% · " + (root.status.battstatus || "")
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Toggle {
              width: parent.width
              visible: root.status.battlimit !== "n/a"
              label: "80% charge limit"
              description: "Caps charging around 80% to slow long-term battery wear"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.battlimit === "on"
              onClicked: root.toggleBatteryLimit()
            }

            Text {
              visible: root.status.battlimit === "n/a"
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Charge limiting is unavailable on this hardware/driver."
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              visible: root.status.fan !== "n/a"
              Text {
                text: "FAN"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: root.status.fan
                options: [
                  { value: "auto", label: "Auto" },
                  { value: "50", label: "50%" },
                  { value: "70", label: "70%" },
                  { value: "100", label: "Max" }
                ]
                onChanged: function(v) { root.setFan(v) }
              }
            }
          }

          } // end generalTab

          // ==================== Keyboard tab ====================
          Column {
            id: keyboardTab
            visible: root.activeTab === "keyboard"
            width: parent.width
            spacing: Style.space(14)

          Column {
            visible: !root.status.kbAvailable
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.status.kbPkgInstalled
                ? "linuwu-sense-dkms is installed, but its driver isn't loaded yet — the stock acer_wmi driver got there first at boot."
                : "Keyboard RGB needs the facer driver (PH315-52, see README) or linuwu-sense-dkms (AUR). Controls below no-op until one is loaded."
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Button {
              visible: root.status.kbPkgInstalled && root.status.helperOk
              text: "Enable keyboard RGB now"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.runEnableKeyboard()
            }
          }

          // ---------- Brightness ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            PanelSectionHeader { text: "BRIGHTNESS"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            ButtonGroup {
              width: parent.width
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              cursorIndex: -1
              options: [
                { value: "0", label: "Off" },
                { value: "25", label: "25%" },
                { value: "50", label: "50%" },
                { value: "75", label: "75%" },
                { value: "100", label: "100%" }
              ]
              onChanged: function(v) { root.setKbBrightness(parseInt(v, 10)) }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Color ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            PanelSectionHeader { text: "COLOR · STATIC"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            Grid {
              width: parent.width
              columns: 5
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(10)
              Repeater {
                model: Model.KB_COLORS
                BorderSurface {
                  id: swatch
                  required property var modelData
                  width: Style.space(28)
                  height: Style.space(28)
                  radius: height / 2
                  color: "#" + Model.kbColorHex(modelData.key, root.status.themeHex, root.modeHex())
                  borderSpec: swatchMouse.containsMouse
                    ? Border.controlSpec("hover-cursor", root.bar.foreground, Color.accent)
                    : Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25), 1)

                  MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setKbColor(Model.kbColorHex(swatch.modelData.key, root.status.themeHex, root.modeHex()))
                  }

                  PanelToolTip {
                    visible: swatchMouse.containsMouse
                    text: swatch.modelData.label
                    fontFamily: root.bar.fontFamily
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Effects ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            PanelSectionHeader { text: "EFFECT"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            Grid {
              id: effectGrid
              readonly property var options: root.status.facerAvailable ? [
                { mode: "1", label: "Breathing" },
                { mode: "2", label: "Neon" },
                { mode: "3", label: "Wave" },
                { mode: "4", label: "Shifting" },
                { mode: "5", label: "Zoom" }
              ] : [
                { mode: "1", label: "Breathing" },
                { mode: "2", label: "Neon" },
                { mode: "3", label: "Wave" },
                { mode: "4", label: "Shifting" },
                { mode: "5", label: "Zoom" },
                { mode: "6", label: "Meteor" },
                { mode: "7", label: "Twinkling" }
              ]
              width: parent.width
              columns: 3
              columnSpacing: Style.spacing.xs
              rowSpacing: Style.spacing.xs

              Repeater {
                model: effectGrid.options
                Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  onClicked: root.setKbEffect(modelData.mode)
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Quick actions ----------
          Row {
            width: parent.width
            spacing: Style.space(10)

            Button {
              text: "Match Omarchy theme"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              selected: root.status.kbLink === "theme"
              onClicked: root.setKbLink("theme")
            }
            Button {
              text: "Match Predator mode"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              selected: root.status.kbLink === "profile"
              onClicked: root.setKbLink("profile")
            }
          }

          } // end keyboardTab

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
