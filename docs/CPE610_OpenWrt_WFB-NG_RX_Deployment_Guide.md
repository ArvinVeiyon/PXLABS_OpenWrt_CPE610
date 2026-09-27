# TP-Link CPE610 v2 — OpenWrt and WFB-NG Installation and Commissioning Manual

| Field | Value |
| --- | --- |
| Document type | Installation and commissioning manual |
| Applies to | TP-Link CPE610 v2 · ath79 / mips_24kc · OpenWrt 24.10.4 · WFB-NG 25.01-r1 |
| Revision | 1.1 |
| Date | 2026-09-27 |
| Status | Current |
| Source document | `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.docx`, converted 2026-09-26 |

> **PRECEDENCE — READ BEFORE USE**
>
> This manual provides the procedure and the supporting rationale. It is **not** the authority
> on parameter values. It was written against `config/master.cfg`, which is the upstream WFB-NG
> template rather than the deployed configuration, and against earlier bench values.
>
> Values found to be incorrect have been corrected in place and are annotated *(corrected)* or
> `# CORRECTED`. The corrections applied are: RF channel 157 → **161**; cluster addressing
> 10.5.6.x → **10.5.7.x**; the `ssh_key` path; `custom_init_script`, which requires an explicit
> `sh` prefix; and the placement of `api_port` and `stats_port`. The original "RX-only, no
> cluster" characterisation is superseded — the node operates as a cluster node.
>
> Where this manual and [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) disagree,
> **`DEPLOYED_PARAMETERS.md` governs.**

---

## 1 Purpose and scope

This manual specifies the complete procedure for deploying WFB-NG on a TP-Link CPE610 v2
running OpenWrt, as the receive node of a WFB-NG cluster. It covers:

- the reason package installation fails on this device, and why custom firmware is mandatory;
- construction of an OpenWrt image with WFB-NG incorporated;
- flashing that image;
- verification of the installed software;
- configuration of the node for cluster operation.

The procedures in this manual were derived from an actual deployment and have been reconciled
against the configuration in force on the unit.

---

## 2 Equipment and software

### 2.1 Hardware

| Component | Specification |
| --- | --- |
| Device | TP-Link CPE610 v2 |
| SoC | Atheros AR9344 |
| CPU architecture | MIPS 24KC |
| Flash | 8 MB |
| RAM | 64 MB |
| Radio | Atheros ath9k, 5 GHz |

### 2.2 Software

| Layer | Version |
| --- | --- |
| OpenWrt | 24.10.4 |
| Target / subtarget | ath79 / generic |
| Package architecture | mips_24kc |
| Root filesystem | squashfs |
| Kernel | 6.6.110 |
| WFB-NG | 25.01-r1, supplied by the official OpenWrt package feed |

---

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
└──────────────────────────────┘
```

**Design basis.**

- The CPE610 contributes receive capability only. Transmit arbitration is won by the relay's
  own adapter in all observed conditions; see `DEPLOYED_PARAMETERS.md` §6.2.
- No packages are installed to the overlay.
- Ethernet carries both cluster control and the recovered packet stream to the relay.

**CORRECTED.** The source document characterised the node as operating with "no cluster". That
characterisation is superseded. The node is a member of `wifibroadcast-cluster@gs`.

---

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

---

## 5 Image types

### 5.1 Factory image

```
openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin
```

Applicable when the device is running TP-Link vendor firmware, for the first OpenWrt
installation.

### 5.2 Sysupgrade image

```
openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

Applicable when OpenWrt is already installed, for upgrading to the custom firmware.

---

## 6 Obtaining the official images

Release directory:

```
https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/
```

```sh
mkdir -p ~/owrt/downloads
cd ~/owrt/downloads

wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin

wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

---

## 7 Constructing the custom firmware

### 7.1 Procedure (ImageBuilder, WFB-NG from the official feed)

**CORRECTED.** The source document instructed the operator to clone `svpcom/wfb-ng` and copy
its package recipes into the build trees. That step is unnecessary. WFB-NG 25.01-r1 is
published in the official OpenWrt 24.10.4 package feed and is resolved automatically by the
ImageBuilder. The procedure below is the one that produced the deployed image.

```sh
cd ~/owrt
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
cd openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64

# Apply the recorded build configuration and package feeds
cp /path/to/PXLABS_OpenWrt_CPE610/config/imagebuilder.config            .config
cp /path/to/PXLABS_OpenWrt_CPE610/config/imagebuilder-repositories.conf repositories.conf

make image PROFILE=tplink_cpe610-v2 \
     PACKAGES="wfb-ng wfb-ng-tun iw ca-bundle -luci -uhttpd -uhttpd-mod-ubus"
```

`kmod-tun`, `libsodium` and `libpcap1` are resolved as dependencies and need not be listed.

**NOTE.** The profile name uses a hyphen: `tplink_cpe610-v2`. Run `make info` to list the valid
profile names for a given target and release.

**NOTE.** No `FILES=` overlay was used for the deployed image. The monitor-interface script was
installed on the unit separately, per Section 10.3. Supplying `FILES=` is a supported option
and would make the node self-sufficient at boot, but it does not describe the deployed
configuration.

### 7.2 Output

```
bin/targets/ath79/generic/
  ├── openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-factory.bin
  └── openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

### 7.3 Optional: building WFB-NG from source (SDK)

This procedure is retained for completeness. It is not required for the deployed configuration,
and it does not reproduce the deployed image. Use it only when a WFB-NG version newer than the
official feed provides is required — for example 25.4.27, which the relay and drone already
run.

```sh
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-sdk-*.tar.zst
cd openwrt-sdk-24.10.4-ath79-generic_*

git clone https://github.com/svpcom/wfb-ng.git
cp -a wfb-ng/openwrt/net/wfb-ng      package/
cp -a wfb-ng/openwrt/net/wfb-ng-full package/

make defconfig
make package/wfb-ng/compile V=s
```

Output:

```
bin/packages/mips_24kc/base/
  ├── wfb-ng_*.ipk
  └── wfb-ng-tun_*.ipk
```

**CAUTION.** These `.ipk` files cannot be installed on the CPE610; see Section 4. They are
usable only as a build input, by staging them in the ImageBuilder's local package repository —
the path declared in `repositories.conf` — and regenerating its package index.

---

## 8 Flashing the firmware

### 8.1 Back up the existing configuration

```sh
sysupgrade -b /tmp/backup.tar.gz
```

### 8.2 Transfer the image

```sh
scp openwrt-*-sysupgrade.bin root@<node-address>:/tmp/
```

### 8.3 Write the image

```sh
sysupgrade -n /tmp/openwrt-*-sysupgrade.bin
```

The `-n` flag discards the existing configuration. It is required when the WFB-NG layout has
changed.

**CAUTION.** The SSH session terminates during the upgrade. Allow 2 to 3 minutes for the
device to reboot. Do not remove power during this period.

---

## 9 Verifying the installation

### 9.1 Binaries

```sh
which wfb_rx
which wfb_tx
```

Expected:

```
/usr/bin/wfb_rx
/usr/bin/wfb_tx
```

### 9.2 Version

```sh
wfb_rx --help
```

Expected:

```
WFB-ng version 25.01-1-openwrt
```

### 9.3 Shared library resolution

```sh
ldd /usr/bin/wfb_rx
```

### 9.4 Installed packages

```sh
opkg list-installed | grep wfb
```

Expected:

```
wfb-ng
wfb-ng-tun
```

**NOTE.** `wfb-server` is not present on the node, and its absence is correct. The node runs
the base package pair and is driven by the relay.

---

## 10 Node configuration

### 10.1 Reference values

| Item | Value |
| --- | --- |
| Relay / centre node (`vind-rly`, Ubuntu or RPi5) | 10.5.7.100 *(corrected)* |
| CPE610 node | 10.5.7.102 *(corrected)* |
| Client / laptop | 10.5.6.50 |
| RF channel | 161, HT20 *(corrected — 5805 MHz)* |
| Monitor interface on the node | `phy0-mon0` |
| WFB link ID | 7669206 |

**Constraint.** The CPE610 has a single radio and cannot sustain station-mode Wi-Fi and a WFB
monitor interface concurrently. Station mode must be stopped before WFB-NG operates.

### 10.2 Disable netifd wireless management

This step prevents OpenWrt from deleting and recreating interfaces, which would destroy
`phy0-mon0`.

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

### 10.3 Install the monitor-interface script

Create `/usr/sbin/wfb-mon0.sh`. The listing below is the script in force on the deployed unit.

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

**NOTE — regulatory domain.** The `iw reg set IN` call in this script is not the effective
setting. The WFB-NG cluster initialisation runs this script first and then re-applies
`iw reg set BO` from the `[cluster]` section, so `BO` is the domain in force. Do not amend the
`IN` value on the assumption that it governs; see `DEPLOYED_PARAMETERS.md` §2.1.

Verify:

```sh
/usr/sbin/wfb-mon0.sh
ip link show phy0-mon0
iw dev phy0-mon0 info
```

The interface must report `type monitor` and the configured channel.

### 10.4 Optional: raise the monitor interface at boot

**NOTE — not the deployed configuration.** The service described in this section is **not**
installed on the deployed node. `phy0-mon0` is created by the relay at each cluster start
through `custom_init_script`. A node rebooted in isolation therefore has no monitor interface
until the relay's cluster service is restarted. Installing this service would make the node
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
logread -e wfb-mon0 | tail -n 50
```

This is a one-shot configuration service. It configures the interface and exits, so `status`
may not report it as running. Confirm the result with `iw dev` instead.

---

## 11 Cluster SSH authentication

Cluster operation requires passwordless SSH from the relay to each node.

### 11.1 Provide a `/bin/bash` path on the node

Cluster SSH invokes remote commands through `/bin/bash`, which OpenWrt does not provide. In its
absence the following error is raised:

```
ash: /bin/bash: not found
```

On the node:

```sh
ln -s /bin/ash /bin/bash 2>/dev/null || true
/bin/bash -c 'echo bash_shim_ok'
```

### 11.2 Generate the cluster key

Perform this once, on the relay. The key path below is the deployed path.

```sh
sudo -i
ssh-keygen -t ed25519 -f /home/vind-admin/.ssh/wfb_cluster_ed25519 -N "" -C "wfb-cluster"
chmod 700 /home/vind-admin/.ssh
chmod 600 /home/vind-admin/.ssh/wfb_cluster_ed25519
```

**CORRECTED.** The source document specified `/root/.ssh/wfb_cluster_ed25519`. The deployed
path is `/home/vind-admin/.ssh/wfb_cluster_ed25519`.

### 11.3 Authorise the key for the local node

The relay's own adapter participates as node `127.0.0.1` and must accept the same key.

```sh
cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@127.0.0.1 'echo LOCAL_NODE_OK'
```

Expected output: `LOCAL_NODE_OK`

### 11.4 Authorise the key on the CPE610 node

```sh
sudo -i
ssh-copy-id -i /home/vind-admin/.ssh/wfb_cluster_ed25519.pub root@10.5.7.102
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo CPE_NODE_OK'
```

Expected output: `CPE_NODE_OK`

Where `ssh-copy-id` is unavailable, append the public key manually. Note that OpenWrt uses
Dropbear, whose authorised-keys file is `/etc/dropbear/authorized_keys`:

```sh
cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub | ssh root@10.5.7.102 "cat >> /etc/dropbear/authorized_keys"
```

---

## 12 Relay cluster configuration

Edit `/etc/wifibroadcast.cfg` on the relay. The cluster comprises two nodes:

| Node | Address | Interface |
| --- | --- | --- |
| Relay's local USB adapter | `127.0.0.1` | `wlx00c0cab6db3b` |
| CPE610 monitor interface | `10.5.7.102` | `phy0-mon0`, created by the script |

```python
[cluster]
nodes = {
  '127.0.0.1':  { 'wlans': ['wlx00c0cab6db3b'] },
  '10.5.7.102': { 'wlans': ['phy0-mon0'],
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
cluster SSH. Without the explicit interpreter the execution fails against the node's `ash`
shell and `phy0-mon0` is never created.

**CAUTION.** Do not pass `--wlans` together with `--cluster`. The two are mutually exclusive
and the server rejects the combination. In cluster mode all interfaces are declared in the
`[cluster] nodes` structure.

Interface names must be stated exactly:

- local node: the actual adapter name on the relay, of the form `wlx…`;
- CPE610 node: the monitor interface name created by the script, `phy0-mon0`.

---

## 13 Cluster operation

Foreground, for commissioning and diagnosis:

```sh
sudo wfb-server --profiles gs --cluster ssh
```

For unattended operation, use the systemd unit `wifibroadcast-cluster@gs.service`. That unit,
its per-profile environment file and the associated troubleshooting procedures are specified in
[`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md)
§5.4 and §5.5.

---

## 14 Commissioning acceptance checks

| # | Check | Expected result |
| --- | --- | --- |
| 1 | `opkg list-installed \| grep wfb` on the node | `wfb-ng` and `wfb-ng-tun` at 25.01-r1 |
| 2 | `iw dev \| grep -A3 phy0-mon0` on the node | Interface present, `type monitor` |
| 3 | `iw dev phy0-mon0 info` on the node | Channel 161, width 20 MHz |
| 4 | Cluster SSH from the relay to `127.0.0.1` and `10.5.7.102` | `LOCAL_NODE_OK`, `CPE_NODE_OK` |
| 5 | `wfb-server --profiles gs --cluster ssh` on the relay | Both nodes register; no `--wlans` conflict raised |
| 6 | Packet statistics for both nodes | Non-zero counts from both; `dec_err: [0, 0]` |

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

The complete parameter set, with the supporting evidence, is specified in
[`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md).
