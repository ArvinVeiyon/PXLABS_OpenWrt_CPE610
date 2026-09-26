# TP-Link CPE610 v2 — OpenWrt + WFB-NG RX Deployment Guide

*Ath79 / MIPS 24KC · OpenWrt 24.10.4 · build, flash, verify, and cluster bring-up*

> ### ⚠ Read `docs/DEPLOYED_PARAMETERS.md` first
>
> This guide is the **narrative build/deploy procedure** and is kept for its reasoning and
> command sequences. It is **not** the authority on parameter values. It was written against
> `config/master.cfg` — which is the *upstream wfb-ng template*, not the deployed config —
> and against earlier bench values.
>
> Values that were wrong here have been corrected inline and marked *(corrected)* or
> `# CORRECTED`. Corrected here: RF channel 157 → **161**, cluster IPs 10.5.6.x → **10.5.7.x**, `ssh_key` path, `custom_init_script` (needs the explicit `sh`), and the `api_port` / `stats_port` placement. The document’s “RX-only, **no cluster**” framing is also obsolete — the node is a cluster node now.
>
> Converted from `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.docx` on 2026-09-26. Where this file and
> [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) disagree, **DEPLOYED_PARAMETERS.md wins.**

---

## 1 Purpose of This Document

This document describes the **complete procedure** to deploy **WFB-NG (RX-only)** on a **TP-Link CPE610 v2** running **OpenWrt**, including:
Why IPK installation fails on this device
Why a **custom OpenWrt firmware** is mandatory
How to **build OpenWrt with WFB-NG included**
How to **flash the firmware**
How to **verify WFB-NG installation**
How to **run WFB-NG in RX-only mode**
This guide is written based on **real deployment experience**, not theory.

## 2 Hardware & Software Overview

### 2.1 Hardware

| Component | Details |
| --- | --- |
| Device | TP-Link CPE610 v2 |
| SoC | Atheros AR9344 |
| CPU Architecture | MIPS 24KC |
| Flash | 8 MB |
| RAM | 64 MB |
| Wi-Fi | Atheros ath9k (5 GHz) |

### 2.2 Software Stack

| Layer | Version |
| --- | --- |
| OpenWrt | 24.10.4 |
| Target | ath79 / generic |
| Architecture | mips_24kc |
| RootFS | squashfs |
| Kernel | 6.6.x |
| WFB-NG | 25.01 (OpenWrt build) |

## 3 Intended Network Topology

Drone (WFB-NG TX)

```sh
        │
        │ 5 GHz raw WiFi
        ▼
┌─────────────────────────────┐
│ TP-Link CPE610 v2            │
│ OpenWrt + WFB-NG             │
│ RX ONLY (monitor mode)       │
│                              │
│ wfb_rx -f                    │
└─────────────┬───────────────┘
              │ Ethernet
              ▼
┌─────────────────────────────┐
│ Relay Station (Linux / RPi) │
│ wfb_rx -a (Aggregator)      │
└─────────────────────────────┘
```

**Key design decision:**
**CPE610 is RX-only**
**No TX, no overlay installs** — *note: the “no cluster” wording here is obsolete; the node IS a `wifibroadcast-cluster@gs` cluster node in the deployed system*
Ethernet is used to forward packets to the relay

## 4 Why IPK Installation Fails on CPE610

### 4.1 Overlay Size Limitation

/overlay size: ~1.3 MB
Available: ~450 KB
WFB-NG dependencies:

| Package | Size |
| --- | --- |
| libstdc++ | ~2.0 MB |
| libsodium | ~200 KB |
| wfb-ng | ~500 KB |

➡ **Overlay cannot fit required libraries**

### 4.2 Observed Error (Expected)

verify_pkg_installable: Only have 480kb available on filesystem /overlay
pkg libstdcpp6 needs 2070

### 4.3 Conclusion

❌ Removing packages does NOT help
❌ Overlay **cannot be resized** on squashfs
❌ External storage is not supported reliably
✅ **Correct solution: Build OpenWrt firmware with WFB-NG baked in**

## 5 OpenWrt Image Types Explained

### 5.1 Factory Image

```sh
openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin
```

Used only when:
Device is running **TP-Link stock firmware**
First OpenWrt installation

### 5.2 Sysupgrade Image

```sh
openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

Used when:
OpenWrt is already installed
Upgrading to custom firmware (WFB-NG included)

## 6 Downloading Official OpenWrt Images

### 6.1 Download Location

https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/

### 6.2 Download Commands

```sh
mkdir -p ~/owrt/downloads
cd ~/owrt/downloads

wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin

wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

## 7 Building WFB-NG IPKs (SDK Method)

### 7.1 Download OpenWrt SDK

```sh
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-sdk-*.tar.zst
cd openwrt-sdk-24.10.4-ath79-generic_*
```

### 7.2 Add WFB-NG Package Source

```sh
git clone https://github.com/svpcom/wfb-ng.git

cp -a wfb-ng/openwrt/net/wfb-ng package/
cp -a wfb-ng/openwrt/net/wfb-ng-full package/
```

### 7.3 Build WFB-NG Packages

```sh
make defconfig
make package/wfb-ng/compile V=s
```

Result:

```sh
bin/packages/mips_24kc/base/
  ├── wfb-ng_*.ipk
  └── wfb-ng-tun_*.ipk
```

⚠ **These IPKs cannot be installed on CPE610**
They are used only to **embed into firmware**

## 8 Building Custom Firmware with ImageBuilder

### 8.1 Download ImageBuilder

```sh
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-imagebuilder-*.tar.zst
cd openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64
```

### 8.2 Add WFB-NG Packages

```sh
mkdir -p package/network/utils
cp -a ~/owrt/wfb-ng/openwrt/net/wfb-ng package/network/utils/
```

### 8.3 Build Firmware for CPE610 v2

```sh
make image PROFILE=tplink_cpe610-v2 \
```

PACKAGES="wfb-ng iw ca-bundle -luci -uhttpd -uhttpd-mod-ubus"

### 8.4 Output Files

```sh
bin/targets/ath79/generic/
  ├── openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin
  └── openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

## 9 Flashing the Custom Firmware

### 9.1 Backup Current Config (Optional)

```sh
sysupgrade -b /tmp/backup.tar.gz
```

### 9.2 Copy Firmware

```sh
scp openwrt-*-sysupgrade.bin root@<CPE_IP>:/tmp/
```

### 9.3 Flash

```sh
sysupgrade /tmp/openwrt-*-sysupgrade.bin
```

⚠ SSH will disconnect during upgrade
⚠ Wait **2–3 minutes** for reboot

## 10 Verifying WFB-NG Installation

### 10.1 Check Binaries

```sh
which wfb_rx
which wfb_tx
```

Expected:

```sh
/usr/bin/wfb_rx
/usr/bin/wfb_tx
```

### 10.2 Check Version

wfb_rx --help
Expected:
WFB-ng version 25.01-1-openwrt

### 10.3 Check Dependencies

```sh
ldd /usr/bin/wfb_rx
```

### 10.4 Check Installed Packages

```sh
opkg list-installed | grep wfb
```

Expected:
wfb-ng
wfb-ng-tun

**WFB-NG Distributed Setup (GS = vind-rly Ubuntu, Node = CPE610 OpenWrt) — Full Procedure**

## 0 Topology and fixed values (your setup)

**GS / Center node:** vind-rly (Ubuntu/RPi5)
**IP:** 10.5.7.100  *(corrected — cluster moved to 10.5.7.0/24)*
**CPE / Node:** CPE610 (OpenWrt)
**IP:** 10.5.7.102  *(corrected)*
**Client/Laptop (example):** 10.5.6.50
**RF channel:** 161 **HT20** *(corrected — 5805 MHz)*
**Monitor interface on CPE:** phy0-mon0
**WFB Link ID:** 7669206
**Important constraint:** CPE is **single radio** → cannot keep STA Wi-Fi and WFB monitor reliably at the same time. When WFB runs, STA must be stopped.

## 3 CPE side (OpenWrt) — install + configure WFB RX forwarding

### 3.1 Confirm WFB tools exist on OpenWrt

On CPE:

```sh
opkg list-installed | grep -i wfb
ls -l /usr/bin/wfb_*
```

Expected: wfb_rx, wfb_tx exist.
(Usually **nowfb-server** on OpenWrt → that’s normal.)

**OpenWrt CPE node (10.5.7.102) — monitor interface setup for cluster-ssh**

## A1 Disable netifd wireless management (important)

We do this so OpenWrt doesn’t delete/recreate interfaces and break phy0-mon0.

```sh
uci set wireless.radio0.disabled='1'
# if you have wifi-iface sections, disable them too (example name may differ):
# uci set wireless.default_radio0.disabled='1'
uci commit wireless
wifi down
```

Confirm wifi is down:

```sh
wifi status
```

## A2 Create the radio init script used by the center node

Create: **/usr/sbin/wfb-mon0.sh**

```sh

cat > /usr/sbin/wfb-mon0.sh <<'EOF'
#!/bin/sh
```

set -e

```sh
# ---- Set your RF settings here ----
```

REG="IN"            # regulatory domain (optional)
CHAN="161"          # channel number (DEPLOYED: 161 = 5805 MHz)
HT="HT20"           # HT20 / HT40+ / HT40-

```sh
# ---- Apply reg domain (best effort) ----
iw reg set "$REG" 2>/dev/null || true

# ---- Recreate monitor interface cleanly ----
iw dev phy0-mon0 del 2>/dev/null || true
iw phy phy0 interface add phy0-mon0 type monitor flags otherbss || true

ip link set phy0-mon0 up
iw dev phy0-mon0 set monitor otherbss 2>/dev/null || true

# ---- Set RF channel ----
iw dev phy0-mon0 set channel "$CHAN" "$HT"
EOF

chmod +x /usr/sbin/wfb-mon0.sh
```

**Test it (must succeed)**

```sh
/usr/sbin/wfb-mon0.sh
ip link show phy0-mon0
iw dev phy0-mon0 info
```

You should see type monitor and your channel.

**Make wfb-mon0.sh a proper OpenWrt service**

cat > /etc/init.d/wfb-mon0 <<'EOF'

```sh
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

**ls -l /etc/rc.d/ | grep wfb-mon0**
**logread-e wfb-mon0 | tail -n 50**

## 8 CPE SSH authentication tweaks

You needed cluster ssh to run remote commands on OpenWrt and hit:
ash: /bin/bash: not found

### 8.1 Fix /bin/bash missing (OpenWrt)

On CPE:

```sh
ln -s /bin/ash /bin/bash 2>/dev/null || true
/bin/bash -c 'echo bash_shim_ok'
```

### 8.2 SSH key-based login (GS → CPE)

On GS, create key if not already:

```sh
sudo mkdir -p /root/.ssh
sudo ssh-keygen -t ed25519 -f /home/vind-admin/.ssh/wfb_cluster_ed25519 -N ""
```

Copy public key to CPE (manual method):

```sh
sudo ssh-copy-id -i /home/vind-admin/.ssh/wfb_cluster_ed25519.pub root@10.5.7.102
```

If ssh-copy-id is not available, do manual:

```sh
sudo cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub | ssh root@10.5.7.102 "cat >> /etc/dropbear/authorized_keys"
```

Now test:

```sh
sudo ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo ok'
```

**B) Center node / Relay GS (10.5.7.100) — local node + cluster keys**
We will run GS as **cluster ssh** with two nodes:
**127.0.0.1** → local USB adapter (wlx00c0cab6db3b)
**10.5.7.102** → CPE monitor (phy0-mon0) created by script

## B1 Generate the cluster SSH key (one-time)

This is the key the center node uses to SSH into nodes.

```sh
sudo -i
ssh-keygen -t ed25519 -f /home/vind-admin/.ssh/wfb_cluster_ed25519 -N "" -C "wfb-cluster"
chmod 700 /root/.ssh
chmod 600 /home/vind-admin/.ssh/wfb_cluster_ed25519
```

**Allow this same key for root@localhost (local node)**

```sh
cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@127.0.0.1 'echo LOCAL_NODE_OK'
```

You must see: LOCAL_NODE_OK

## B2 Copy the public key to the CPE (node) for passwordless SSH

From center node:

```sh
sudo -i
ssh-copy-id -i /home/vind-admin/.ssh/wfb_cluster_ed25519.pub root@10.5.7.102
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo CPE_NODE_OK'
```

You must see: CPE_NODE_OK

**C) Update /etc/wifibroadcast.cfg (center node) — cluster with local node + CPE node**
Edit:

```sh
sudo nano /etc/wifibroadcast.cfg
```

Use this **cluster** block (keep it exactly like this style):

```sh
[cluster]
nodes = {
  '127.0.0.1':  { 'wlans': ['wlx00c0cab6db3b'] },
  '10.5.7.102': { 'wlans': ['phy0-mon0'], 'custom_init_script': 'sh /usr/sbin/wfb-mon0.sh' }
}
ssh_user = 'root'
ssh_port = 22
ssh_key = '/home/vind-admin/.ssh/wfb_cluster_ed25519'   # DEPLOYED path, not /root
```

server_address = '10.5.7.100'
base_port_server = 10000
base_port_node = 11000
# CORRECTED: api_port/stats_port are NOT read from [cluster].
# They belong in the profile section:  [gs] stats_port = 8003 / api_port = 8103
**Important notes**
Do **NOT** run --wlans together with --cluster (that’s why you got the CLI error earlier).
The node “wlans” names must be:
local: the real USB iface name on center node (wlx...)
CPE: the monitor iface name created by script (phy0-mon0)

## 9 Run cluster (foreground or background)

### 9.1 Foreground

```sh
sudo wfb-server --profiles gs --cluster ssh
```
