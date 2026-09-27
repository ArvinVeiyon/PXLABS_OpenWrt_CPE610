# TP-Link CPE610 v2 — OpenWrt and WFB-NG Installation and Commissioning Manual

| Field | Value |
| --- | --- |
| Document type | Installation and commissioning manual |
| Applies to | TP-Link CPE610 v2 · ath79 / mips_24kc · OpenWrt 24.10.4 · WFB-NG 25.01-r1 |
| Revision | 2.0 |
| Date | 2026-09-27 |
| Status | Current |
| Source document | `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.docx`, converted 2026-09-26 |

> **PRECEDENCE — READ BEFORE USE**
>
> This manual specifies the **procedure**. It is not the authority on **parameter values**.
> All deployed parameter values are specified in
> [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md), which governs wherever the two documents
> disagree.
>
> Values found to be incorrect in the source document have been corrected in place and are
> annotated *(corrected)* or `# CORRECTED`. The corrections applied are listed in Appendix A.

**Procedure sequence.** This manual is written to be executed in order, from firmware
construction through to commissioning acceptance:

| Part | Sections | Activity |
| --- | --- | --- |
| I | 1–5 | Preparation, architecture and file locations |
| II | 6–8 | Build the firmware with WFB-NG included |
| III | 9–12 | Flash the firmware and verify the installation |
| IV | 13–17 | Configure the node |
| V | 18–21 | Configure the relay and establish the cluster connection |
| VI | 22 | Commissioning acceptance verification |

---

# Part I — Preparation

## 1 Purpose and scope

This manual specifies the complete procedure for deploying WFB-NG on a TP-Link CPE610 v2
running OpenWrt, as the receive node of a WFB-NG cluster. It covers:

- the reason package installation fails on this device, and why custom firmware is mandatory;
- construction of an OpenWrt image with WFB-NG incorporated;
- flashing that image and verifying the installed software;
- configuration of the node, including the monitor-interface script;
- configuration of the relay connection and the cluster service;
- acceptance verification of scripts, services and link operation.

Parameter values are out of scope and are specified in
[`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md). Relay-side subject matter beyond the
cluster connection — MAVLink routing, QGroundControl behaviour and flight-mode selection — is
maintained in the `Relay_Station_Pxlabs` repository.

## 2 Equipment and software

### 2.1 Hardware

| Component | Specification |
| --- | --- |
| Device | TP-Link CPE610 v2 |
| SoC | Atheros AR9344 |
| CPU architecture | MIPS 24KC |
| Flash | 8 MB |
| RAM | 64 MB |
| Radio | Atheros ath9k, 5 GHz, single radio |

### 2.2 Software

| Layer | Version |
| --- | --- |
| OpenWrt | 24.10.4 (`r28959-29397011cc`) |
| Target / subtarget | ath79 / generic |
| Package architecture | mips_24kc |
| Root filesystem | squashfs |
| Kernel | 6.6.110 |
| WFB-NG | 25.01-r1, supplied by the official OpenWrt package feed |

### 2.3 Build host requirements

A Linux x86-64 host with network access, approximately 2 GB of free disk space for the
ImageBuilder, and the packages `wget`, `tar` with zstd support, `make`, `gawk`, `python3` and
`unzip`.

## 3 Deployment architecture

The CPE610 provides a monitor interface. The receive and transmit processes are started on it
remotely by the relay over cluster SSH. The node does not run `wfb-server`.

```
        Drone (WFB-NG TX)
               │
               │  5 GHz raw Wi-Fi — ch 161 / 5805 MHz / HT20  (corrected)
               ▼
┌──────────────────────────────┐
│ TP-Link CPE610 v2            │
│ OpenWrt + WFB-NG             │
│ Monitor interface phy0-mon0  │
│ 10.5.7.102        (corrected)│
└──────────────┬───────────────┘
               │  Ethernet
               ▼
┌──────────────────────────────┐
│ Relay station (Linux / RPi5) │
│ wfb-server --cluster ssh     │
│ 10.5.7.100        (corrected)│
└──────────────┬───────────────┘
               │  Wi-Fi, 10.5.6.0/24
               ▼
      Laptop / ground station 10.5.6.50
```

**Design basis.**

- The CPE610 contributes receive capability only. Transmit arbitration is won by the relay's
  own adapter in all observed conditions; see `DEPLOYED_PARAMETERS.md` §6.2.
- No packages are installed to the node's overlay.
- Ethernet carries both cluster control and the recovered packet stream to the relay.

**CORRECTED.** The source document characterised the node as operating with "no cluster". That
characterisation is superseded. The node is a member of `wifibroadcast-cluster@gs`.

## 4 Constraint: package installation is not achievable on this device

### 4.1 Overlay capacity

| Quantity | Value |
| --- | --- |
| `/overlay` total | approximately 1.3 MB |
| `/overlay` available | approximately 450 KB |

Dependency sizes:

| Package | Approximate size |
| --- | --- |
| `libstdc++` | 2.0 MB |
| `libsodium` | 200 KB |
| `wfb-ng` | 500 KB |

The available overlay capacity cannot accommodate the required libraries.

### 4.2 Observed error

```
verify_pkg_installable: Only have 480kb available on filesystem /overlay
pkg libstdcpp6 needs 2070
```

This error is expected on this platform and does not indicate a fault.

### 4.3 Determination

| Candidate remedy | Outcome |
| --- | --- |
| Removing installed packages | Does not recover sufficient capacity |
| Resizing `/overlay` | Not possible on squashfs |
| External storage | Not dependable on this platform |
| **Incorporating WFB-NG into the firmware image** | **Required approach** |

## 5 File locations

All paths used in this manual are listed here. Section 5.2 defines shell variables that the
subsequent procedures reference, so that the commands may be executed as written.

### 5.1 Path register

**Build host**

| Purpose | Path |
| --- | --- |
| This repository | `/home/pxlabs/PXLABS_OpenWrt_CPE610` |
| Build trees root | `/home/pxlabs/owrt` |
| ImageBuilder tree | `/home/pxlabs/owrt/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64` |
| OpenWrt SDK tree (optional, §8.3 only) | `/home/pxlabs/owrt/openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64` |
| Upstream WFB-NG clone (optional, §8.3 only) | `/home/pxlabs/owrt/wfb-ng` |
| Download staging | `/home/pxlabs/owrt/downloads` |
| Build output | `<ImageBuilder>/bin/targets/ath79/generic` |

**Repository contents referenced by this manual**

| Purpose | Path |
| --- | --- |
| ImageBuilder build configuration | `config/imagebuilder.config` |
| ImageBuilder package feeds | `config/imagebuilder-repositories.conf` |
| SDK build configuration (optional) | `config/sdk.config`, `config/sdk-feeds.conf.default` |
| Released firmware images | `images/custom/` |
| Stock recovery images | `images/stock/` |
| Vendor configuration backup | `stock-firmware/CPE610-v2_stock_config.bin` |
| Parameter reference (authoritative) | `docs/DEPLOYED_PARAMETERS.md` |
| Record of the node's monitor script | `deployment/usr/sbin/wfb-mon0.sh` |
| Record of the relay link configuration | `deployment/wifibroadcast.cfg.relay` |

**Node (CPE610)**

| Purpose | Path |
| --- | --- |
| Monitor-interface script | `/usr/sbin/wfb-mon0.sh` |
| Optional boot service | `/etc/init.d/wfb-mon0` |
| Network configuration | `/etc/config/network` |
| Wireless configuration | `/etc/config/wireless` |
| Authorised SSH keys (Dropbear) | `/etc/dropbear/authorized_keys` |
| WFB-NG binaries | `/usr/bin/wfb_rx`, `/usr/bin/wfb_tx`, `/usr/bin/wfb_tun` |

**Relay**

| Purpose | Path |
| --- | --- |
| Link and cluster configuration | `/etc/wifibroadcast.cfg` |
| Cluster SSH private key | `/home/vind-admin/.ssh/wfb_cluster_ed25519` *(corrected)* |
| Authorised SSH keys | `/root/.ssh/authorized_keys` |
| Cluster systemd unit | `/etc/systemd/system/wifibroadcast-cluster@.service` |
| Per-profile environment file | `/etc/default/wifibroadcast.gs` |

### 5.2 Shell variables

Define these on the build host before executing Part II. Re-define them in each new shell.

```sh
export REPO=/home/pxlabs/PXLABS_OpenWrt_CPE610
export OWRT=/home/pxlabs/owrt
export IB=$OWRT/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64
export SDK=$OWRT/openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64
export NODE=10.5.7.102        # CPE610 node        (corrected)
export RELAY=10.5.7.100       # relay LAN address  (corrected)
```

**NOTE.** Where this manual is applied to a different installation, amend the addresses in
`$NODE` and `$RELAY` and the tree names under `$OWRT` to match that installation. The remainder
of the procedure is unchanged.

---

# Part II — Build the firmware

## 6 Retrieve the ImageBuilder

```sh
mkdir -p "$OWRT"
cd "$OWRT"

wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst

cd "$IB"
```

Optionally retrieve the official stock images, which are also committed at
`$REPO/images/stock/` and are required only for recovery:

```sh
mkdir -p "$OWRT/downloads" && cd "$OWRT/downloads"
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

## 7 Build the image with WFB-NG included

**CORRECTED.** The source document instructed the operator to clone `svpcom/wfb-ng` and copy its
package recipes into the build trees. That step is unnecessary. WFB-NG 25.01-r1 is published in
the official OpenWrt 24.10.4 package feed and is resolved automatically by the ImageBuilder,
provided the feed is declared in `repositories.conf`. The procedure below is the one that
produced the deployed image.

```sh
cd "$IB"

# Apply the recorded build configuration and package feeds.
# imagebuilder-repositories.conf declares the official feed that supplies WFB-NG 25.01-r1.
cp "$REPO/config/imagebuilder.config"            .config
cp "$REPO/config/imagebuilder-repositories.conf" repositories.conf

# Build both images. The profile name uses a hyphen: tplink_cpe610-v2
make image PROFILE=tplink_cpe610-v2 \
     PACKAGES="wfb-ng wfb-ng-tun iw ca-bundle -luci -uhttpd -uhttpd-mod-ubus"
```

`kmod-tun`, `libsodium` and `libpcap1` are resolved as dependencies and need not be listed.

**NOTE.** Profile names vary by target and release. Run `make info` in the ImageBuilder tree to
list the valid names.

**NOTE — `FILES=` overlay not used.** No `FILES=` overlay was applied to the deployed image. The
ImageBuilder tree contains no `files/` directory, and neither `/usr/sbin/wfb-mon0.sh` nor
`/etc/init.d/wfb-mon0` is present in the built root filesystem. The monitor-interface script was
installed on the unit separately, per Section 15. Supplying `FILES=` is a supported option and
would make the node self-sufficient at boot, but it does not describe the deployed
configuration.

## 8 Verify the build output

### 8.1 Locate and identify the images

```sh
cd "$IB/bin/targets/ath79/generic"
ls -l *cpe610-v2*.bin
cat sha256sums
```

Expected files:

```
openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin
openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

### 8.2 Confirm WFB-NG is present in the image

```sh
grep -i wfb "$IB/bin/targets/ath79/generic/"*.manifest
```

Expected:

```
wfb-ng - 25.01-r1
wfb-ng-tun - 25.01-r1
```

**CAUTION.** If this returns nothing, WFB-NG was not incorporated. Do not flash the image.
Confirm that `repositories.conf` was copied per Section 7 and that the build host had network
access to `downloads.openwrt.org`.

Compare against the released reference:

```sh
grep -i wfb "$REPO/images/custom/"*.manifest
```

### 8.3 Optional: build WFB-NG from source

This procedure is not required for the deployed configuration and does not reproduce the
deployed image. Use it only where a WFB-NG version newer than the official feed provides is
required — for example 25.4.27, which the relay and drone already run.

The recipes previously held in this repository were superseded and have been removed; obtain the
recipes from upstream.

```sh
cd "$OWRT"
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
cd "$SDK"

# Obtain the package recipes from upstream
git clone https://github.com/svpcom/wfb-ng.git "$OWRT/wfb-ng"
cp -a "$OWRT/wfb-ng/openwrt/net/wfb-ng"      package/
cp -a "$OWRT/wfb-ng/openwrt/net/wfb-ng-full" package/

# Apply the recorded SDK build configuration
cp "$REPO/config/sdk-feeds.conf.default" feeds.conf.default
./scripts/feeds update -a && ./scripts/feeds install -a
cp "$REPO/config/sdk.config" .config
make defconfig

make package/wfb-ng/compile V=s
```

Output is written to `$SDK/bin/packages/mips_24kc/base/`.

**CAUTION.** The resulting `.ipk` files cannot be installed on the CPE610; see Section 4. They
are usable only as a build input. To incorporate them, stage them in the ImageBuilder's local
package repository — the path declared in `repositories.conf` — and regenerate that
repository's package index with `scripts/ipkg-make-index.sh` before running `make image`. An
empty or absent index causes the packages to be silently ignored and the feed version to be
used instead.

`wfb-ng` provides the binaries only and is the package pair the node runs. `wfb-ng-full` adds
the Python control plane and `wfb-server`, declares `CONFLICTS:=wfb-ng`, and is substantially
larger; assess it against the CPE610 flash budget before selecting it.

---

# Part III — Flash the firmware

## 9 Select the image

| Starting state of the device | Image | Applied by |
| --- | --- | --- |
| TP-Link Pharos vendor firmware | **factory** | Vendor web interface |
| Existing OpenWrt installation | **sysupgrade** | `sysupgrade` on the device |

## 10 Back up the existing configuration

For a device already running OpenWrt:

```sh
ssh root@$NODE 'sysupgrade -b /tmp/backup.tar.gz'
scp root@$NODE:/tmp/backup.tar.gz ./backup-$(date +%F).tar.gz
```

**NOTE.** For a device still running vendor firmware, export the vendor configuration through
the Pharos web interface before conversion. The backup taken from this unit is retained at
`$REPO/stock-firmware/CPE610-v2_stock_config.bin`. It is the only route back to the vendor
configuration and is to be preserved.

## 11 Flash the image

### 11.1 From vendor firmware — factory image

Apply
`openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin`
through the Pharos web interface firmware-upgrade function. The device reboots into OpenWrt at
its default address, 192.168.1.1.

### 11.2 From an existing OpenWrt installation — sysupgrade image

```sh
cd "$IB/bin/targets/ath79/generic"
scp openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin root@$NODE:/tmp/

ssh root@$NODE 'sysupgrade -n /tmp/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin'
```

The `-n` flag discards the existing configuration. It is required when the WFB-NG layout has
changed. Omitting it preserves `/etc/config`, in which case Sections 13 and 14 may already be
satisfied.

**CAUTION.** The SSH session terminates during the upgrade. Allow 2 to 3 minutes for the device
to reboot. Do not remove power during this period.

## 12 Verify the installation

Perform every check in this section before proceeding to Part IV.

### 12.1 Release identification

```sh
ssh root@$NODE 'cat /etc/openwrt_release'
```

Expected: `24.10.4`, `r28959-29397011cc`, target `ath79/generic`.

### 12.2 WFB-NG binaries

```sh
ssh root@$NODE 'ls -l /usr/bin/wfb_*'
```

Expected: `wfb_rx`, `wfb_tx`, `wfb_tun`.

### 12.3 WFB-NG version

```sh
ssh root@$NODE 'wfb_rx --help 2>&1 | head -1'
```

Expected:

```
WFB-ng version 25.01-1-openwrt
```

### 12.4 Installed packages

```sh
ssh root@$NODE 'opkg list-installed | grep wfb'
```

Expected:

```
wfb-ng - 25.01-r1
wfb-ng-tun - 25.01-r1
```

**NOTE.** `wfb-server` is not present on the node, and its absence is correct. The node runs the
base package pair and is driven by the relay. A command of the form `wfb-server --version` will
fail on the node and is not a valid verification step there.

### 12.5 Shared library resolution

```sh
ssh root@$NODE 'ldd /usr/bin/wfb_rx'
```

No entry may report `not found`. A missing `libstdcpp6`, `libsodium` or `libpcap1` indicates
that the image was built without the required dependencies.

---

# Part IV — Configure the node

## 13 Node network interface

Confirm or set the static LAN address.

```sh
ssh root@$NODE
uci set network.lan.proto='static'
uci set network.lan.ipaddr='10.5.7.102'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network restart
```

Resulting configuration:

```
# /etc/config/network
config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '10.5.7.102'
    option netmask '255.255.255.0'
    option ip6assign '60'
```

**NOTE.** The node has no default route and no package feed, by design. See
`DEPLOYED_PARAMETERS.md` §6.1.

## 14 Disable netifd wireless management

This step prevents OpenWrt from deleting and recreating interfaces, which would destroy
`phy0-mon0`. The radio is dedicated to WFB monitor mode; a concurrent station or access-point
configuration conflicts with it. Management access remains available over Ethernet.

```sh
uci set wireless.radio0.disabled='1'
# If wifi-iface sections are present, disable them as well; the section name may differ:
# uci set wireless.default_radio0.disabled='1'
uci commit wireless
wifi down
```

Confirm:

```sh
wifi status
```

## 15 Install the monitor-interface script

Create `/usr/sbin/wfb-mon0.sh` on the node. The listing below is the script in force on the
deployed unit; the reference copy is at `$REPO/deployment/usr/sbin/wfb-mon0.sh`.

```sh
cat > /usr/sbin/wfb-mon0.sh <<'EOF'
#!/bin/sh
set -e

# Regulatory domain. See the note below: this value is not the effective domain.
iw reg set IN 2>/dev/null || true

# Recreate the monitor interface cleanly
iw dev phy0-mon0 del 2>/dev/null || true
iw phy phy0 interface add phy0-mon0 type monitor flags otherbss || true

ip link set phy0-mon0 up

# Set the channel explicitly. DEPLOYED: channel 161 = 5805 MHz.
# Use one of the following:
iw dev phy0-mon0 set channel 161 HT20 || true
# or: iw dev phy0-mon0 set freq 5805 HT20 || true

iw dev phy0-mon0 set monitor otherbss 2>/dev/null || true
EOF

chmod +x /usr/sbin/wfb-mon0.sh
```

**NOTE — regulatory domain.** The `iw reg set IN` call is not the effective setting. The WFB-NG
cluster initialisation runs this script first and then re-applies `iw reg set BO` from the
`[cluster]` section, so `BO` is the domain in force. Do not amend the `IN` value on the
assumption that it governs; see `DEPLOYED_PARAMETERS.md` §2.1.

**NOTE — channel value.** The channel in this script must match `wifi_channel` in the relay's
`[cluster]` configuration. The deployed value is 161. Confirm against
`DEPLOYED_PARAMETERS.md` §2 before deviating.

Verify the script in isolation:

```sh
/usr/sbin/wfb-mon0.sh
ip link show phy0-mon0
iw dev phy0-mon0 info
```

The interface must report `type monitor` and channel 161, width 20 MHz.

## 16 Optional: raise the monitor interface at boot

**NOTE — not the deployed configuration.** The service in this section is **not** installed on
the deployed node. `phy0-mon0` is created by the relay at each cluster start through
`custom_init_script`. A node rebooted in isolation therefore has no monitor interface until the
relay's cluster service is restarted. Installing this service would make the node
self-sufficient at boot; it is a sound improvement, but it does not describe the configuration
in force. See `DEPLOYED_PARAMETERS.md` §7.

```sh
cat > /etc/init.d/wfb-mon0 <<'EOF'
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

Verify:

```sh
ls -l /etc/rc.d/ | grep wfb-mon0
/etc/init.d/wfb-mon0 status
logread -e wfb-mon0 | tail -n 50
```

This is a one-shot configuration service: it configures the interface and exits. `status` may
therefore not report it as running. Confirm the result with `iw dev`.

## 17 Provide a `/bin/bash` path

Cluster SSH invokes remote commands through `/bin/bash`, which OpenWrt does not provide. In its
absence the following error is raised during cluster start:

```
ash: /bin/bash: not found
```

On the node:

```sh
ln -s /bin/ash /bin/bash 2>/dev/null || true
/bin/bash -c 'echo bash_shim_ok'
```

Expected output: `bash_shim_ok`

---

# Part V — Configure the relay and establish the cluster connection

## 18 Relay interfaces and reachability

Confirm that both relay interfaces are up and that the node is reachable.

| Interface | Address | Peer |
| --- | --- | --- |
| Wi-Fi, towards the laptop | 10.5.6.101/24 | Laptop 10.5.6.50 |
| LAN, towards the node | 10.5.7.100/24 | CPE610 10.5.7.102 |

```sh
ip -4 addr show | grep -E '10\.5\.(6|7)\.'
ping -c 3 $NODE
ssh root@$NODE 'echo node_reachable'
```

**NOTE.** `server_address` must be the relay LAN address, 10.5.7.100. It is the only address
every node can reach. Two subnets are in use: the cluster operates on 10.5.7.0/24, while video
and client traffic operate on 10.5.6.0/24.

## 19 Cluster SSH key setup

Cluster operation requires passwordless SSH from the relay to every node, including
`127.0.0.1` where the relay's own adapter participates as a local node.

### 19.1 Generate the cluster key

Perform this once, on the relay.

```sh
sudo -i
ssh-keygen -t ed25519 -f /home/vind-admin/.ssh/wfb_cluster_ed25519 -N "" -C "wfb-cluster"
chmod 700 /home/vind-admin/.ssh
chmod 600 /home/vind-admin/.ssh/wfb_cluster_ed25519
```

**CORRECTED.** The source document specified `/root/.ssh/wfb_cluster_ed25519`. The deployed path
is `/home/vind-admin/.ssh/wfb_cluster_ed25519`.

### 19.2 Authorise the key for the local node

```sh
cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@127.0.0.1 'echo LOCAL_NODE_OK'
```

Expected output: `LOCAL_NODE_OK`

### 19.3 Authorise the key on the CPE610 node

```sh
ssh-copy-id -i /home/vind-admin/.ssh/wfb_cluster_ed25519.pub root@$NODE
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@$NODE 'echo CPE_NODE_OK'
```

Expected output: `CPE_NODE_OK`

Where `ssh-copy-id` is unavailable, append the public key manually. OpenWrt uses Dropbear,
whose authorised-keys file is `/etc/dropbear/authorized_keys`:

```sh
cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub | ssh root@$NODE "cat >> /etc/dropbear/authorized_keys"
```

## 20 Relay cluster configuration

Edit `/etc/wifibroadcast.cfg` on the relay.

> **PARAMETER VALUES.** The values below are reproduced for procedural continuity only.
> [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) is the authoritative reference for every
> parameter in this file — RF settings in §2, cluster topology and addressing in §3, ports in
> §4, streams and FEC in §5. Verify against it before applying. A captured copy of the deployed
> file is at `$REPO/deployment/wifibroadcast.cfg.relay`.

The cluster comprises two nodes:

| Node | Address | Interface |
| --- | --- | --- |
| Relay's local USB adapter | `127.0.0.1` | `wlx00c0cab6db3b` |
| CPE610 monitor interface | `10.5.7.102` | `phy0-mon0`, created by the script |

```python
[cluster]
nodes = {
  '127.0.0.1':  { 'wlans': ['wlx00c0cab6db3b'] },
  '10.5.7.102': { 'wlans': ['phy0-mon0'],
                  'wifi_txpower': None,
                  'custom_init_script': 'sh /usr/sbin/wfb-mon0.sh' }
}
ssh_user = 'root'
ssh_port = 22
ssh_key = '/home/vind-admin/.ssh/wfb_cluster_ed25519'   # CORRECTED: deployed path, not /root
server_address = '10.5.7.100'
base_port_server = 10000
base_port_node = 11000

# CORRECTED: api_port and stats_port are NOT read from [cluster].
# They belong in the profile section:
#   [gs]
#   stats_port = 8003
#   api_port   = 8103
```

**CORRECTED — `custom_init_script` requires the `sh` prefix.** The script is invoked over
cluster SSH. Without the explicit interpreter the execution fails against the node's `ash` shell
and `phy0-mon0` is never created.

**CAUTION.** Do not pass `--wlans` together with `--cluster`. The two are mutually exclusive and
the server rejects the combination. In cluster mode all interfaces are declared in the
`[cluster] nodes` structure.

Interface names must be stated exactly:

- local node: the actual adapter name on the relay, of the form `wlx…`;
- CPE610 node: the monitor interface name created by the script, `phy0-mon0`.

## 21 Cluster service

### 21.1 Foreground operation, for commissioning

```sh
sudo wfb-server --profiles gs --cluster ssh
```

Both nodes must register. Leave this running while performing the Section 22 checks, then stop
it before enabling the service.

### 21.2 Unattended operation

Install and enable the systemd unit. The unit definition, its per-profile environment file and
the associated troubleshooting procedures are specified in
[`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md)
§5.4 and §5.5.

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now wifibroadcast.service
sudo systemctl enable --now wifibroadcast-cluster@gs.service

systemctl status wifibroadcast-cluster@gs.service
journalctl -u wifibroadcast-cluster@gs.service -f
```

---

# Part VI — Commissioning acceptance verification

## 22 Acceptance checks

Perform every check. Record the result against each item. A failure in items 1 to 6 must be
resolved before proceeding.

### 22.1 Node — firmware and software

| # | Check | Command | Expected result |
| --- | --- | --- | --- |
| 1 | OpenWrt release | `cat /etc/openwrt_release` | 24.10.4, `r28959-29397011cc` |
| 2 | WFB-NG packages | `opkg list-installed \| grep wfb` | `wfb-ng` and `wfb-ng-tun` at 25.01-r1 |
| 3 | Binaries present | `ls -l /usr/bin/wfb_*` | `wfb_rx`, `wfb_tx`, `wfb_tun` |
| 4 | Libraries resolve | `ldd /usr/bin/wfb_rx` | No `not found` entries |

### 22.2 Node — scripts and services

| # | Check | Command | Expected result |
| --- | --- | --- | --- |
| 5 | Monitor script present and executable | `ls -l /usr/sbin/wfb-mon0.sh` | Mode includes `x` |
| 6 | Monitor script runs standalone | `/usr/sbin/wfb-mon0.sh; echo rc=$?` | `rc=0` |
| 7 | `/bin/bash` path present | `/bin/bash -c 'echo bash_shim_ok'` | `bash_shim_ok` |
| 8 | Boot service, if installed per §16 | `/etc/init.d/wfb-mon0 status` | `OK: phy0-mon0 exists` |
| 9 | Boot service enabled, if installed | `ls -l /etc/rc.d/ \| grep wfb-mon0` | `S25wfb-mon0`, `K10wfb-mon0` |

**NOTE.** Items 8 and 9 do not apply to the deployed configuration, in which the service is not
installed. Record them as not applicable.

### 22.3 Node — radio state

| # | Check | Command | Expected result |
| --- | --- | --- | --- |
| 10 | Monitor interface exists | `iw dev \| grep -A3 phy0-mon0` | Interface present, `type monitor` |
| 11 | Channel and width | `iw dev phy0-mon0 info` | Channel 161, 5805 MHz, width 20 MHz |
| 12 | Managed radio disabled | `uci get wireless.radio0.disabled` | `1` |
| 13 | Interface is up | `ip link show phy0-mon0` | State `UP` |

### 22.4 Relay — connection and cluster

| # | Check | Command (on the relay) | Expected result |
| --- | --- | --- | --- |
| 14 | Node reachable | `ping -c 3 10.5.7.102` | 0% packet loss |
| 15 | Local-node SSH | `ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@127.0.0.1 'echo LOCAL_NODE_OK'` | `LOCAL_NODE_OK` |
| 16 | Node SSH | `ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo CPE_NODE_OK'` | `CPE_NODE_OK` |
| 17 | Configuration parses | `python3 -c "import configparser,sys;c=configparser.ConfigParser();c.read('/etc/wifibroadcast.cfg');print(len(c.sections()),'sections')"` | Section count reported, no exception |
| 18 | Cluster service active | `systemctl is-active wifibroadcast-cluster@gs.service` | `active` |
| 19 | Service log clean | `journalctl -u wifibroadcast-cluster@gs.service -n 50` | No `Permission denied`, no `/bin/bash: not found`, no `--wlans` conflict |

### 22.5 Link operation

| # | Check | Expected result |
| --- | --- | --- |
| 20 | Both nodes registered in the cluster | Two nodes listed; the CPE610 at 10.5.7.102 with `phy0-mon0` |
| 21 | Packet statistics | Non-zero received counts from **both** nodes |
| 22 | FEC decode errors | `dec_err: [0, 0]` |
| 23 | Node RSSI plausible | ath9k reports absolute dBm, approximately −23 to −21; SNR reads 0 |
| 24 | Video at the ground station | Stream present at 10.5.6.50:5600 |

**NOTE — expected asymmetry.** The relay's adapter wins transmit arbitration in all observed
conditions, and the node reports SNR 0. Both are expected and are not commissioning failures;
see `DEPLOYED_PARAMETERS.md` §6.2. Item 21 requires only that the node's received count is
non-zero, demonstrating that its receive contribution is active.

### 22.6 Post-commissioning record

On completion, record the following with the commissioning result:

- the image file name and its SHA-256, from `$IB/bin/targets/ath79/generic/sha256sums`;
- the output of `opkg list-installed` from the node;
- the output of `iw dev phy0-mon0 info`;
- the `[cluster]` section of the relay's `/etc/wifibroadcast.cfg` as applied.

Where the deployed configuration is changed, update
[`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) and the records under
`$REPO/deployment/` to match.

---

## Appendix A — Corrections applied to the source document

| Item | Source document | Corrected value |
| --- | --- | --- |
| RF channel | 157 (5785 MHz) | **161 (5805 MHz), HT20** |
| Cluster addressing | 10.5.6.100 / 10.5.6.102 | **10.5.7.100 / 10.5.7.102** |
| `ssh_key` | `/root/.ssh/wfb_cluster_ed25519` | **`/home/vind-admin/.ssh/wfb_cluster_ed25519`** |
| `custom_init_script` | `/usr/sbin/wfb-mon0.sh` | **`sh /usr/sbin/wfb-mon0.sh`** |
| `api_port` / `stats_port` | 8203 / 8303 in `[cluster]` | **8103 / 8003 in `[gs]`** |
| Node role | "RX only, no cluster" | **Cluster node of `wifibroadcast-cluster@gs`** |
| WFB-NG source | Clone `svpcom/wfb-ng` and copy recipes | **Official OpenWrt 24.10.4 package feed** |
| Boot-time monitor service | Presented as required | **Not installed; the relay creates the interface at cluster start** |
| Build command | Included `FILES=files/` | **No `FILES=` overlay; no `files/` tree exists** |

## Appendix B — Related documents

| Document | Content |
| --- | --- |
| [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) | **Authoritative** parameter reference: RF, cluster topology, addressing, ports, streams and FEC, security findings |
| [`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md) | Cluster deployment manual: systemd unit definition, per-profile environment, troubleshooting |
| [`CPE610_Operations_and_Maintenance_Manual.md`](CPE610_Operations_and_Maintenance_Manual.md) | Operations and maintenance: routine checks, logging, restart order, fault isolation, recovery and rollback, replacement units |
| `../README.md` | Technical reference: WFB-NG provenance, repository layout, image records, exclusions |
| `../deployment/README.md` | Configuration records annex: the configuration in force on the node |
