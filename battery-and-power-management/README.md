# Battery & Power Management Plugin

A lightweight, efficient battery status bar widget and interactive control popup designed for the **Noctalia** desktop shell environment.

This plugin displays real-time battery diagnostics (including dynamic power draw in Watts) and provides desktop controls to switch system power profiles or adjust hardware battery charge thresholds safely without needing root privileges.

## Features


*   **Live Diagnostics Bar**: Displays current charge percentage, charging/discharging state, and accurate power consumption or charging rate dynamically calculated in Watts (`W`).
*   **Power Profiles Switcher**: Quick native toggle buttons utilizing `powerprofilesctl` backend to alternate between `power-saver`, `balanced`, and `performance` states.
*   **Hardware Charge Threshold Slider**: A fluid, customized multi-step UI slider to set the battery charge limit (inclusive range from `50%` to `100%`) directly interacting with the kernel via `/sys/class/power_supply/BAT0/charge_control_end_threshold`.

## System Requirements & Prerequisites

To ensure the threshold operations and power profile modifications function smoothly, the following system utilities must be available:

1.  **Power Profiles Daemon**: Ensure `powerprofilesctl` is installed and running on your system.
    
        # Verify daemon status
        systemctl status power-profiles-daemon.service
    
2.  **Supported Hardware Platform**: A modern laptop kernel exposure that supports hardware threshold ceilings via standard `sysfs` (e.g., Lenovo ThinkPad running kernel `5.17+`).

## Installation & Setup

### 1\. Copy the Assets

Ensure all `.qml` files are placed inside your local Noctalia deployment layout:

    mkdir -p ~/.config/noctalia/plugins/battery-watt/

### 2\. Configure Udev Permissions for the Threshold Slider

By default, files under `/sys/` require root access. To allow the QML runtime layer to adjust limits on the fly safely, a custom udev rule matching a dedicated hardware communication group must be registered.

Navigate to your plugin directory and run the initialization script:

    cd ~/.config/noctalia/plugins/battery-watt/
    chmod +x setup_rules.sh
    sudo ./setup_rules.sh

> **Note:** This script creates a secure `battery_ctl` group, adds your current user to it, links the `99-battery-threshold.rules` configuration into your system's directory (`/etc/udev/rules.d/`), and refreshes the active udev configurations.

### 3\. Apply Group Membership Changes

For the new group access configurations to apply directly to your current user session, you must log out of your window manager environment completely and log back in.

### 4\. Restart the Shell Environment

Once permissions are initialized, trigger a reload or restart your Noctalia desktop interface instance to initialize the components:

    killall quickshell
    noctalia

## Diagnostics and Monitoring

To verify your system state or monitor live events and verify that the plugin correctly captures kernel-level interactions:

*   **Check Current Kernel Value**:
    
        cat /sys/class/power_supply/BAT0/charge_control_end_threshold
    
*   **Inspect Shell Runtime Logs**:
    
    Monitor stdout logs for validation errors or property mismatches when interacting with the custom UI sliders.