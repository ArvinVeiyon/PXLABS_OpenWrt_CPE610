#!/bin/sh
set -e

# Country/reg (optional but good)
iw reg set IN 2>/dev/null || true

# Recreate monitor iface cleanly
iw dev phy0-mon0 del 2>/dev/null || true
iw phy phy0 interface add phy0-mon0 type monitor flags otherbss || true

ip link set phy0-mon0 up

# IMPORTANT: set channel explicitly (example: 5805 MHz = ch161)
# Choose ONE of these:
iw dev phy0-mon0 set channel 161 HT20 || true
# or: iw dev phy0-mon0 set freq 5805 HT20 || true

iw dev phy0-mon0 set monitor otherbss 2>/dev/null || true
