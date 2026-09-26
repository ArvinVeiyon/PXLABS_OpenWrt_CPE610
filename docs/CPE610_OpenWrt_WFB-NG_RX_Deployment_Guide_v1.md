# CPE610 + WFB-NG RX Node Deployment Guide (cluster / distributed)

*OpenWrt 24.10.x · ImageBuilder firmware · RX-only CPE node + relay-station cluster (ssh mode)*  
*Original document dated 27 Dec 2025.*

> ### ⚠ Read `docs/DEPLOYED_PARAMETERS.md` first
>
> This guide is the **narrative build/deploy procedure** and is kept for its reasoning and
> command sequences. It is **not** the authority on parameter values. It was written against
> `config/master.cfg` — which is the *upstream wfb-ng template*, not the deployed config —
> and against earlier bench values.
>
> Values that were wrong here have been corrected inline and marked *(corrected)* or
> `# CORRECTED`. Corrected here: RF channel 157 → **161** (5805 MHz), `ssh_key` path, and the `api_port` / `stats_port` placement. This revision’s IP plan (10.5.7.0/24) is already correct and matches deployment.
>
> Converted from `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.docx` on 2026-09-26. Where this file and
> [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) disagree, **DEPLOYED_PARAMETERS.md wins.**

---

## 1. Purpose

This document describes the production-ready deployment for an RX-only TP-Link CPE610 running OpenWrt 24.10.x as a WFB-NG cluster node, controlled from a Raspberry Pi 5 relay station acting as the WFB-NG cluster server (center node). The laptop/ground station connects to the relay over Wi‑Fi; the relay connects to the CPE over Ethernet (LAN).
Key goals:
- Avoid overlay space exhaustion on OpenWrt: WFB-NG is baked into a custom sysupgrade image using ImageBuilder (preferred).
- CPE runs only the monitor interface setup (radio config). WFB traffic processes (wfb_rx/wfb_tx) are started remotely by the relay via cluster ssh mode.
- Relay uses cluster ssh mode with BOTH: (a) remote CPE node and (b) local USB Wi‑Fi adapter as a local node (127.0.0.1).
- Relay exports decoded video/MAVLink to the Laptop (10.5.6.50).

## 2. Network Topology and IP Plan

Fixed addresses used in this setup:

| Component / Interface | IP / Notes |
| --- | --- |
| Laptop (Ground Station) | 10.5.6.50/24 (Wi‑Fi to Relay) |
| Relay Station Wi‑Fi interface (to Laptop) | 10.5.6.101/24 |
| Relay Station LAN interface (to CPE) | 10.5.7.100/24  (Cluster server_address) |
| CPE610 LAN IP | 10.5.7.102/24 (cluster node) |

Physical connections:
- Laptop ⇄ Relay: Wi‑Fi (10.5.6.0/24).
- Relay ⇄ CPE610: Ethernet (10.5.7.0/24).
- CPE610 radio: monitor interface (phy0-mon0) on the chosen WFB channel (**deployed: ch 161 / 5805 MHz / HT20**).

## 3. OpenWrt Firmware Strategy (IMPORTANT)

Because the CPE610 overlay storage is limited, installing WFB-NG via opkg/ipk on-device can quickly exhaust overlay space. The recommended method is to build a custom sysupgrade image using OpenWrt ImageBuilder and bake in the required WFB-NG packages.
References:
- • WFB-NG Distributed Operation wiki: https://github.com/svpcom/wfb-ng/wiki/Distributed-operation
- • WFB-NG Setup HOWTO: https://github.com/svpcom/wfb-ng/wiki/Setup-HOWTO

### 3.1 Build Custom sysupgrade Image using ImageBuilder

Use ImageBuilder matching your target/subtarget. Example below must match your CPE610 hardware and the OpenWrt release.
8.1 Download ImageBuilder (Custom sysupgrade build; recommended to avoid overlay space usage from opkg/ipk installs)
Bake required packages into firmware (WFB-NG baked-in via ImageBuilder):

```sh
# IMPORTANT:
# - We bake WFB-NG into the firmware image (sysupgrade) to avoid overlay space constraints.
# - This method builds one clean image you can flash and reuse for other CPE610 v2 units.

# One-time: clone WFB-NG (contains the OpenWrt package recipe)
mkdir -p ~/owrt && cd ~/owrt
git clone https://github.com/svpcom/wfb-ng.git

# Enter the ImageBuilder directory you downloaded/extracted above
cd ~/owrt/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64

# Inject (or refresh) the WFB-NG package recipe into ImageBuilder
mkdir -p package/network/utils
cp -a ~/owrt/wfb-ng/openwrt/net/wfb-ng package/network/utils/
# OPTIONAL (recommended): bake our CPE radio scripts into firmware using FILES="files"
# Example files tree (created later in this guide):
#   files/usr/sbin/wfb-mon0.sh
#   files/etc/init.d/wfb-mon0
#   files/etc/config/wireless   (optional – if you want Wi‑Fi disabled by default)

# Build the sysupgrade image (correct profile name uses a dash: tplink_cpe610-v2)
make image PROFILE="tplink_cpe610-v2" PACKAGES="wfb-ng wfb-ng-tun" FILES="files"

# Output sysupgrade image will be under:
#   bin/targets/ath79/generic/*cpe610-v2*-sysupgrade.bin
```

Notes:
• PROFILE name differs by target/version; run `make info` in ImageBuilder to list valid PROFILE names.
• If you already have a working build command in your environment, keep using it and only ensure that `wfb-ng` is included.
• The purpose here is to avoid post-install via opkg on the CPE.

### 3.2 Flash sysupgrade image

```sh
# Copy the generated sysupgrade.bin to the CPE (example)
scp openwrt-24.10.4-...-tplink_cpe610-v2-squashfs-sysupgrade.bin root@10.5.7.102:/tmp/

# Flash (CPE)
ssh root@10.5.7.102
sysupgrade -n /tmp/openwrt-24.10.4-...-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

After reboot, verify WFB-NG is present (no opkg install required):
wfb-server --version || /usr/bin/wfb-server --version
opkg list-installed | grep -i wfb-ng || true

## 4. CPE610 Configuration (RX Node)

The CPE610 runs OpenWrt and provides a monitor interface (phy0-mon0) for WFB-NG. The relay station starts the WFB processes remotely via cluster ssh mode.

### 4.1 Network on CPE (LAN)

Ensure br-lan has the static address:

```sh
# /etc/config/network (example)
config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '10.5.7.102'
    option netmask '255.255.255.0'
    option ip6assign '60'
```

### 4.2 Disable normal Wi‑Fi management on the CPE radio

The CPE radio is dedicated to WFB monitor mode. If the radio is also configured as STA/AP, it will conflict with monitor mode.

```sh
# /etc/config/wireless
# Keep radio present but disable regular wifi-iface sections
# (You can still manage the CPE via Ethernet at 10.5.7.102)
uci set wireless.radio0.disabled='1'
uci commit wireless
wifi down
```

### 4.3 Create monitor interface at boot (wfb-mon0.sh)

OpenWrt 24.10+ may not create a Wi‑Fi interface when Wi‑Fi is disabled, and WFB cluster ssh init expects a monitor interface. Therefore we use a custom init script to reliably create and configure phy0-mon0.
Create /usr/sbin/wfb-mon0.sh on the CPE:

```sh
cat >/usr/sbin/wfb-mon0.sh <<'EOF'

#!/bin/sh
```

set -e

```sh
# Country/reg (optional but good)
iw reg set IN 2>/dev/null || true
# Recreate monitor iface cleanly
iw dev phy0-mon0 del 2>/dev/null || true
iw phy phy0 interface add phy0-mon0 type monitor flags otherbss || true
ip link set phy0-mon0 up
# IMPORTANT: set channel explicitly (DEPLOYED: 5805 MHz = ch161)
# Choose ONE of these:
iw dev phy0-mon0 set channel 161 HT20 || true
# or: iw dev phy0-mon0 set freq 5805 HT20 || true
iw dev phy0-mon0 set monitor otherbss 2>/dev/null || true

EOF
chmod +x /usr/sbin/wfb-mon0.sh
```

### 4.4 Enable wfb-mon0 at startup (OpenWrt init script)

This is a boot-time radio setup service. It configures the monitor interface and exits. Because it’s a one-shot setup, `status` may not show it as running — verify with `iw dev`.

```sh
cat >/etc/init.d/wfb-mon0 <<'EOF'

#!/bin/sh /etc/rc.common
START=25
STOP=10
start() {
    /bin/sh /usr/sbin/wfb-mon0.sh
}
stop() {
    ip link del phy0-mon0 2>/dev/null || true
}
status() {
    if iw dev 2>/dev/null | grep -q "Interface phy0-mon0"; then
        echo "OK: phy0-mon0 exists"
        iw dev phy0-mon0 info 2>/dev/null | sed 's/^/  /'
        return 0
    else
        echo "NOT OK: phy0-mon0 missing"
        return 1
    fi
}

EOF
chmod +x /etc/init.d/wfb-mon0

/etc/init.d/wfb-mon0 enable
/etc/init.d/wfb-mon0 start
```

Verification:

```sh
iw dev | grep -A3 -E 'phy0-mon0|type monitor'
ifconfig phy0-mon0 || ip link show phy0-mon0
```

### 4.5 Shutdown / reboot commands (CPE)

```sh
# Clean shutdown
poweroff

# Reboot
reboot
```

## 5. Relay Station (Cluster Server) Setup

Relay station runs WFB-NG server (center node) and controls remote nodes (CPE + optional local node) using cluster ssh mode.

### 5.1 Network on Relay

Ensure these two interfaces are up and reachable:
- Wi‑Fi towards Laptop: 10.5.6.101/24 (Laptop = 10.5.6.50).
- LAN towards CPE: 10.5.7.100/24 (CPE = 10.5.7.102).

### 5.2 WFB-NG cluster ssh keys (IMPORTANT)

Cluster ssh mode requires passwordless SSH from relay (root) to each node, including localhost (127.0.0.1) if you use a local node.
#Fix /bin/bash missing (OpenWrt)
On CPE:

```sh
ln -s /bin/ash /bin/bash 2>/dev/null || true
/bin/bash -c 'echo bash_shim_ok'

# On relay (as root)
sudo -i
ssh-keygen -t ed25519 -f /root/.ssh/wfb_cluster_ed25519 -N "" -C "wfb-cluster"
cat /root/.ssh/wfb_cluster_ed25519.pub >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# Test localhost auth (must work)
ssh -i /root/.ssh/wfb_cluster_ed25519 root@127.0.0.1 'echo LOCAL_NODE_OK'
```

Copy the same public key to the CPE (authorized_keys):

```sh
# On relay:
ssh-copy-id -i /root/.ssh/wfb_cluster_ed25519.pub root@10.5.7.102

# Test:
ssh -i /root/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo CPE_NODE_OK'
```

### 5.3 /etc/wifibroadcast.cfg (cluster + local node)

Below is the critical cluster section. The key points:
• server_address MUST be the relay LAN IP (10.5.7.100).
• Add the CPE node (10.5.7.102) with its monitor interface (phy0-mon0).
• Add a local node entry (127.0.0.1) when you want to include the relay’s local USB Wi‑Fi adapter in the cluster.
• For RX-only CPE node, set wifi_txpower='off' and (optionally) keep only rx usage.

```sh

[cluster]
nodes = {'127.0.0.1': {'wlans': ['wlx00c0cab6db3b']}, '10.5.7.102': {'wlans': ['phy0-mon0'],'wifi_txpower': None,'custom_init_script': '/usr/sbin/wfb-mon0.sh'}}
ssh_user = 'root'
ssh_port = 22
ssh_key = '/home/vind-admin/.ssh/wfb_cluster_ed25519'   # DEPLOYED path, not /root
```

server_address = '10.5.7.100'
base_port_server = 10000
base_port_node = 11000
# CORRECTED: api_port/stats_port are NOT read from [cluster].
# They belong in the profile section:  [gs] stats_port = 8003 / api_port = 8103
Note: The `custom_init_script` is especially important on OpenWrt 24.10+ where Wi‑Fi may not be initialized if disabled (see Distributed Operation wiki).

### 5.4 Systemd service: wifibroadcast-cluster@gs.service (IMPORTANT)

Cluster mode MUST NOT use `--wlans`. The server reads `[cluster] nodes` from /etc/wifibroadcast.cfg. Use the following unit as the authoritative service for cluster operation.

```sh
# /etc/systemd/system/wifibroadcast-cluster@.service
[Unit]
Description=WFB-ng CLUSTER server, profile %i
Requires=wifibroadcast.service
ReloadPropagatedFrom=wifibroadcast.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
# common environment
EnvironmentFile=/etc/default/wifibroadcast
# per-profile environment
EnvironmentFile=-/etc/default/wifibroadcast.%i

# IMPORTANT: cluster mode uses config [cluster] nodes from /etc/wifibroadcast.cfg
# No --wlans here.
ExecStart=/bin/bash -c "exec /usr/bin/wfb-server --profiles $(echo %i | tr : ' ') --cluster ${WFB_CLUSTER_MODE:-ssh}"

KillMode=mixed
TimeoutStopSec=5s
Restart=on-failure
RestartSec=5s
StandardError=inherit

[Install]
WantedBy=wifibroadcast.service
```

Enable and start:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now wifibroadcast.service
sudo systemctl enable --now wifibroadcast-cluster@gs.service

# Logs
journalctl -u wifibroadcast-cluster@gs.service -f
```

### 5.5 What is /etc/default/wifibroadcast.gs ?

Systemd units can load environment variables per profile. `/etc/default/wifibroadcast.gs` is an optional per-profile file used to set variables only for the `gs` profile (for example choosing cluster mode ssh vs manual).

```sh
# /etc/default/wifibroadcast.gs
# cluster mode: ssh or manual
WFB_CLUSTER_MODE=ssh
```

## 6. Troubleshooting Cheatsheet

### 6.1 'argument --wlans not allowed with --cluster'

This is expected: in cluster mode you do NOT pass --wlans on the server command line. Instead, define all node wlans in /etc/wifibroadcast.cfg under [cluster]. Use wifibroadcast-cluster@gs.service (provided in this document).

### 6.2 'Unable to decrypt packet'

Usually indicates key mismatch (gs.key vs drone.key) or wrong peer. Confirm that /etc/gs.key on relay matches the transmitter side keypair, and that the configured channel/bandwidth match.

### 6.3 'ip: SIOCGIFFLAGS: No such device' on the CPE node

The monitor interface is missing. Ensure /usr/sbin/wfb-mon0.sh exists and is executable, and that /etc/init.d/wfb-mon0 is enabled and ran successfully. Verify with `iw dev`.

### 6.4 Cluster ssh fails (Permission denied)

Ensure the relay’s /root/.ssh/wfb_cluster_ed25519.pub is in each node’s /root/.ssh/authorized_keys (including localhost if using 127.0.0.1 as a node).

### 6.5 MCS tuning note (why RSSI/‘dBm’ may look better at MCS 1)

Lower MCS uses more robust modulation/coding, which often improves effective link quality and reduces packet loss. Some OSD/telemetry displays may show higher (better) RSSI/quality when the link is not saturating or losing frames. Treat MCS as a stability/range vs throughput knob.

## Appendix A: Quick Start Commands

```sh
# Relay (cluster server)
sudo systemctl restart wifibroadcast-cluster@gs.service
# Verify WFB is running and nodes are connected:
wfb-cli status || true

# CPE: verify monitor is present
iw dev | grep -A3 phy0-mon0
```
