import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen: null
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property string screenName: screen ? (screen.name ?? "") : ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(root.screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(root.screenName)
    readonly property string fixedFont: Settings.data?.ui?.fontFixed ?? "monospace"

    property int batPercent: 0
    property real wattNum: 0.0
    property string batStatus: pluginApi.tr("battery.status_unknown")
    property string timeRemaining: "..."
    
    property string currentProfile: "balanced"
    property int batteryThreshold: 80

    readonly property real contentWidth: layout.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight
    implicitWidth: contentWidth
    implicitHeight: Style.barHeight

    // ===== Helpers =====

    function parseEta(out) {
        if (!out) return "...";
        let lines = out.split("\n");
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (line.indexOf("time to empty:") === 0 || line.indexOf("time to full:") === 0) {
                let value = line.substring(line.indexOf(":") + 1).trim();
                return formatUpowerTime(value);
            }
        }
        return "...";
    }

    function formatUpowerTime(value) {
        let parts = value.split(/\s+/);
        let num = parseFloat(parts[0]);
        let unit = parts.length > 1 ? parts[1] : "";
        if (isNaN(num)) return "...";
        let minutes = 0;
        if (unit.indexOf("hour") === 0) minutes = num * 60;
        else if (unit.indexOf("minute") === 0) minutes = num;
        else if (unit.indexOf("second") === 0) minutes = num / 60;
        else if (unit.indexOf("day") === 0) minutes = num * 1440;
        else return value;
        let total = Math.round(minutes);
        let h = Math.floor(total / 60);
        let m = total % 60;
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    // ===== Power Profiles =====

    Process {
        id: profileGetter
        command: ["powerprofilesctl", "get"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                root.currentProfile = data.trim();
            }
        }
    }

    Process {
        id: profileSetter
        running: false
    }

    function updatePowerProfile() {
        profileGetter.running = true;
    }

    function setPowerProfile(profile) {
        profileSetter.command = ["powerprofilesctl", "set", profile];
        profileSetter.running = true;
        root.currentProfile = profile;
    }

    Component.onCompleted: {
        if (pluginApi) {
            pluginApi.mainInstance = root;
        }
        updatePowerProfile();
        thresholdLoader.reload();
    }

    // ===== Battery Logic =====

    function setBatteryThreshold(value) {
        root.batteryThreshold = value;
        let devPath = pluginApi?.pluginSettings?.batteryDevice ?? "/sys/class/power_supply/BAT0";
        thresholdSetter.running = false;
        thresholdSetter.command = ["sh", "-c", "echo " + value + " > " + devPath + "/charge_control_end_threshold"];
        thresholdSetter.running = true;
    }

    Process {
        id: thresholdSetter
        onExited: (code) => {
            if (code !== 0) {
                Logger.e("BatteryAndPowerManagement", "Error writing battery threshold.");
            }
        }
    }

    // ===== ETA via upower =====

    Process {
        id: etaGetter
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.timeRemaining = root.parseEta(text);
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.timeRemaining = "...";
            }
        }
    }

    Timer {
        id: globalRefreshTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let devPath = pluginApi?.pluginSettings?.batteryDevice ?? "/sys/class/power_supply/BAT0";
            let dev = devPath.split("/").pop() || "BAT0";
            batLoader.device = dev;
            batLoader.reload();
            thresholdLoader.reload();

            etaGetter.running = false;
            etaGetter.command = ["upower", "-i", "/org/freedesktop/UPower/devices/battery_" + dev];
            etaGetter.running = true;
        }
    }

    FileView {
        id: thresholdLoader
        path: (pluginApi?.pluginSettings?.batteryDevice ?? "/sys/class/power_supply/BAT0") + "/charge_control_end_threshold"
        printErrors: false
        onLoaded: {
            let val = text();
            if (val) {
                let parsed = parseInt(val.trim());
                if (!isNaN(parsed) && parsed >= 50 && parsed <= 100) root.batteryThreshold = parsed;
            }
        }
    }

    FileView {
        id: batLoader
        property string device: "BAT0"
        path: "/sys/class/power_supply/" + device + "/uevent"
        printErrors: false

        onLoaded: {
            let content = text();
            if (!content) return;

            let lines = content.split("\n");
            let cap = 0, rate = 0;
            let statusRaw = "Unknown";

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line.indexOf("POWER_SUPPLY_CAPACITY=") === 0) cap = parseInt(line.split("=")[1]) || 0;
                else if (line.indexOf("POWER_SUPPLY_POWER_NOW=") === 0) rate = parseInt(line.split("=")[1]) || 0;
                else if (line.indexOf("POWER_SUPPLY_STATUS=") === 0) statusRaw = line.split("=")[1] || "Unknown";
            }

            root.batPercent = cap;
            
            if (statusRaw === "Charging") root.batStatus = pluginApi.tr("battery.status_charging");
            else if (statusRaw === "Full") root.batStatus = pluginApi.tr("battery.status_full");
            else if (statusRaw === "Discharging") root.batStatus = pluginApi.tr("battery.status_discharging");
            else if (statusRaw === "Not charging") root.batStatus = pluginApi.tr("battery.status_not_charging");
            else root.batStatus = pluginApi.tr("battery.status_unknown");

            root.wattNum = rate / 1000000.0;
        }
    }

    // ===== UI =====
    Rectangle {
        id: visualCapsule
        anchors.centerIn: parent
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusL
        
        color: mouseArea.containsMouse 
            ? Color.mHover 
            : (root.batStatus === pluginApi.tr("battery.status_charging") ? Color.mPrimary : Style.capsuleColor)

        border.color: root.batStatus === pluginApi.tr("battery.status_charging") ? Color.mPrimary : Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: layout
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                icon: (root.batStatus === pluginApi.tr("battery.status_charging") || root.batStatus === pluginApi.tr("battery.status_full")) ? "battery-charging" : "battery-4"
                color: mouseArea.containsMouse || root.batStatus === pluginApi.tr("battery.status_charging") ? Color.mOnPrimary : Color.mOnSurface
            }

            NText {
                text: root.batPercent + "% " + (root.batStatus === pluginApi.tr("battery.status_charging") ? "+" : "-") + root.wattNum.toFixed(1) + "W"
                pointSize: barFontSize
                font.family: root.fixedFont
                font.weight: Font.Bold
                color: mouseArea.containsMouse || root.batStatus === pluginApi.tr("battery.status_charging") ? Color.mOnPrimary : Color.mOnSurface
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.updatePowerProfile();
            thresholdLoader.reload();
            pluginApi.openPanel(root.screen, root);
        }
    }
}