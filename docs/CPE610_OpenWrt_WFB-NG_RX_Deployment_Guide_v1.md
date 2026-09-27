# CPE610 and WFB-NG Receive Node — Cluster Deployment Manual

| Field | Value |
| --- | --- |
| Document type | Operational deployment manual (distributed / cluster operation) |
| Applies to | TP-Link CPE610 v2 receive node and relay-station cluster server, SSH cluster mode |
| Revision | 1.1 |
| Date | 2026-09-27 |
| Status | Current |
| Source document | `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.docx`, dated 27 Dec 2025, converted 2026-09-26 |

> **PRECEDENCE — READ BEFORE USE**
>
> This manual provides the procedure and the supporting rationale. It is **not** the authority
> on parameter values. It was written against `config/master.cfg`, which is the upstream WFB-NG
> template rather than the deployed configuration, and against earlier bench values.
>
> Values found to be incorrect have been corrected in place and are annotated *(corrected)* or
> `# CORRECTED`. The corrections applied are: RF channel 157 → **161** (5805 MHz); the
> `ssh_key` path; `custom_init_script`, which requires an explicit `sh` prefix; and the
> placement of `api_port` and `stats_port`. The addressing plan in this revision
> (10.5.7.0/24) is already correct and matches deployment.
>
> Where this manual and [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) disagree,
> **`DEPLOYED_PARAMETERS.md` governs.**

**Related documents.**

| Document | Content |
| --- | --- |
| [`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md) | Installation and commissioning manual: the complete sequential procedure from firmware construction through flashing, node configuration and commissioning acceptance. Use that document for a first installation; use this one for cluster-specific configuration, the systemd unit and troubleshooting. |
| [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) | **Authoritative** parameter reference |
| [`CPE610_Operations_and_Maintenance_Manual.md`](CPE610_Operations_and_Maintenance_Manual.md) | Operations and maintenance: the node in service — routine checks, logging, restart order, fault isolation, recovery and rollback |
| `../README.md` | Technical reference: WFB-NG provenance, repository layout, image records |
| `../deployment/README.md` | Configuration records annex |

---

## 1 Purpose

This manual specifies the production deployment of a receive-only TP-Link CPE610 running
OpenWrt 24.10.x as a WFB-NG cluster node, controlled from a Raspberry Pi 5 relay station acting
as the WFB-NG cluster server (centre node). The laptop or ground station connects to the relay
over Wi-Fi; the relay connects to the CPE610 over Ethernet.

Deployment objectives:

- Avoid overlay-capacity exhaustion on the node. WFB-NG is incorporated into a custom
  sysupgrade image by means of the OpenWrt ImageBuilder.
- Restrict the node's local responsibility to monitor-interface configuration. The WFB-NG
  traffic processes, `wfb_rx` and `wfb_tx`, are started remotely by the relay in SSH cluster
  mode.
- Operate the relay in SSH cluster mode with both node types present: the remote CPE610 node,
  and the relay's own USB Wi-Fi adapter as a local node at `127.0.0.1`.
- Export decoded video and MAVLink from the relay to the laptop at 10.5.6.50.

---

## 2 Network topology and addressing

| Component or interface | Address and notes |
| --- | --- |
| Laptop (ground station) | 10.5.6.50/24, Wi-Fi to the relay |
| Relay Wi-Fi interface, towards the laptop | 10.5.6.101/24 |
| Relay LAN interface, towards the node | 10.5.7.100/24 — the cluster `server_address` |
| CPE610 LAN address | 10.5.7.102/24, cluster node |

Physical connections:

| Link | Medium | Subnet |
| --- | --- | --- |
| Laptop ⇄ relay | Wi-Fi | 10.5.6.0/24 |
| Relay ⇄ CPE610 | Ethernet | 10.5.7.0/24 |
| Drone ⇄ CPE610 radio | 5 GHz monitor interface `phy0-mon0` | Channel 161 / 5805 MHz / HT20 *(corrected)* |

---

## 3 Firmware strategy

Overlay storage on the CPE610 is limited, and installing WFB-NG on the device by way of
`opkg` exhausts it. The required method is to build a custom sysupgrade image with the WFB-NG
packages incorporated, using the OpenWrt ImageBuilder.

Upstream references:

- WFB-NG distributed operation: https://github.com/svpcom/wfb-ng/wiki/Distributed-operation
- WFB-NG setup procedure: https://github.com/svpcom/wfb-ng/wiki/Setup-HOWTO

### 3.1 Build the custom sysupgrade image

Use an ImageBuilder matching the target, subtarget and OpenWrt release of the device.

**CORRECTED.** The source document instructed the operator to clone `svpcom/wfb-ng` and copy
its package recipe into the ImageBuilder tree. That step is unnecessary. WFB-NG 25.01-r1 is
published in the official OpenWrt 24.10.4 package feed and is resolved automatically, provided
the feed is declared in `repositories.conf`. The procedure below is the one that produced the
deployed image.

Paths are as registered in the installation manual,
[`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md)
§5:

```sh
export REPO=/home/pxlabs/PXLABS_OpenWrt_CPE610
export OWRT=/home/pxlabs/owrt
export IB=$OWRT/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64
```

```sh
# Enter the ImageBuilder tree retrieved and extracted for this target
cd "$IB"

# Apply the recorded build configuration and package feeds.
# imagebuilder-repositories.conf declares the official feed that supplies WFB-NG 25.01-r1.
cp "$REPO/config/imagebuilder.config"            .config
cp "$REPO/config/imagebuilder-repositories.conf" repositories.conf

# Build the images. The profile name uses a hyphen: tplink_cpe610-v2
make image PROFILE="tplink_cpe610-v2" \
     PACKAGES="wfb-ng wfb-ng-tun iw ca-bundle -luci -uhttpd -uhttpd-mod-ubus"

# Output:
#   $IB/bin/targets/ath79/generic/*cpe610-v2*-sysupgrade.bin
```

Confirm that WFB-NG was incorporated before flashing:

```sh
grep -i wfb "$IB/bin/targets/ath79/generic/"*.manifest
# expected: wfb-ng - 25.01-r1   /   wfb-ng-tun - 25.01-r1
```

**NOTE.** Profile names vary by target and release. Run `make info` in the ImageBuilder to list
the valid names.

**NOTE — optional `FILES=` overlay.** The ImageBuilder accepts `FILES="files"` to incorporate a
file tree into the image, for example:

```
files/usr/sbin/wfb-mon0.sh
files/etc/init.d/wfb-mon0
files/etc/config/wireless
```

This option was **not** used for the deployed image. The monitor-interface script was installed
on the unit separately, per Section 4.3. Using `FILES=` would make the node self-sufficient at
boot and is a sound improvement, but it does not describe the deployed configuration.

### 3.2 Flash the sysupgrade image

```sh
# Transfer the image to the node
scp openwrt-24.10.4-...-tplink_cpe610-v2-squashfs-sysupgrade.bin root@10.5.7.102:/tmp/

# Write the image, on the node
ssh root@10.5.7.102
sysupgrade -n /tmp/openwrt-24.10.4-...-tplink_cpe610-v2-squashfs-sysupgrade.bin
```

**CAUTION.** The SSH session terminates during the upgrade. Allow 2 to 3 minutes for the reboot
and do not remove power during this period.

After reboot, confirm that WFB-NG is present and that no `opkg install` step is required:

```sh
opkg list-installed | grep -i wfb-ng
ls -l /usr/bin/wfb_*
```

**NOTE.** `wfb-server` is not present on the node, and its absence is correct. The node runs the
base `wfb-ng` and `wfb-ng-tun` pair and is driven by the relay. Commands of the form
`wfb-server --version` will fail on the node and are not a valid verification step there.

---

## 4 Node configuration

The node provides a monitor interface, `phy0-mon0`, for WFB-NG. The relay starts the WFB-NG
processes remotely in SSH cluster mode.

### 4.1 Node LAN interface

Confirm that `br-lan` carries the static address:

```
# /etc/config/network
config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '10.5.7.102'
    option netmask '255.255.255.0'
    option ip6assign '60'
```

### 4.2 Disable normal Wi-Fi management on the node radio

The radio is dedicated to WFB monitor mode. A concurrent station or access-point configuration
conflicts with monitor mode. Management access remains available over Ethernet at 10.5.7.102.

```sh
uci set wireless.radio0.disabled='1'
uci commit wireless
wifi down
```

### 4.3 Install the monitor-interface script

OpenWrt 24.10 and later may not create a Wi-Fi interface when the radio is disabled, while the
WFB-NG cluster initialisation requires a monitor interface to be present. A configuration
script is therefore used to create and configure `phy0-mon0` deterministically.

The listing below is the script in force on the deployed unit.

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

### 4.4 Optional: raise the monitor interface at boot

**NOTE — not the deployed configuration.** The service described in this section is **not**
installed on the deployed node. `phy0-mon0` is created by the relay at each cluster start
through `custom_init_script`. A node rebooted in isolation therefore has no monitor interface
until the relay's cluster service is restarted. See `DEPLOYED_PARAMETERS.md` §7.

This is a boot-time configuration service: it configures the interface and exits. Because it is
a one-shot service, `status` may not report it as running. Confirm the result with `iw dev`.

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

Verification:

```sh
iw dev | grep -A3 -E 'phy0-mon0|type monitor'
ip link show phy0-mon0
```

### 4.5 Shutdown and reboot

```sh
poweroff        # clean shutdown
reboot          # restart
```

**CAUTION.** Rebooting the node in isolation leaves it without a monitor interface until the
relay's cluster service is restarted. Where the node is restarted during maintenance, restart
`wifibroadcast-cluster@gs.service` on the relay afterwards.

---

## 5 Relay configuration (cluster server)

The relay runs the WFB-NG server as the centre node and controls the remote node and the
optional local node in SSH cluster mode.

### 5.1 Relay interfaces

Confirm that both interfaces are up and reachable:

| Interface | Address | Peer |
| --- | --- | --- |
| Wi-Fi, towards the laptop | 10.5.6.101/24 | Laptop 10.5.6.50 |
| LAN, towards the node | 10.5.7.100/24 | CPE610 10.5.7.102 |

### 5.2 Cluster SSH keys

SSH cluster mode requires passwordless SSH from the relay to every node, including `127.0.0.1`
where a local node is used.

**Provide a `/bin/bash` path on the node.** Cluster SSH invokes remote commands through
`/bin/bash`, which OpenWrt does not provide. In its absence the error `ash: /bin/bash: not
found` is raised. On the node:

```sh
ln -s /bin/ash /bin/bash 2>/dev/null || true
/bin/bash -c 'echo bash_shim_ok'
```

**Generate the cluster key on the relay.** The path below is the deployed path.

```sh
sudo -i
ssh-keygen -t ed25519 -f /home/vind-admin/.ssh/wfb_cluster_ed25519 -N "" -C "wfb-cluster"
cat /home/vind-admin/.ssh/wfb_cluster_ed25519.pub >> /root/.ssh/authorized_keys
chmod 700 /home/vind-admin/.ssh
chmod 600 /home/vind-admin/.ssh/wfb_cluster_ed25519
chmod 600 /root/.ssh/authorized_keys

# Verify local-node authentication; this must succeed
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@127.0.0.1 'echo LOCAL_NODE_OK'
```

**CORRECTED.** The source document specified `/root/.ssh/wfb_cluster_ed25519`. The deployed
path is `/home/vind-admin/.ssh/wfb_cluster_ed25519`.

**Authorise the same key on the node.**

```sh
# On the relay
ssh-copy-id -i /home/vind-admin/.ssh/wfb_cluster_ed25519.pub root@10.5.7.102

# Verify
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo CPE_NODE_OK'
```

Expected outputs: `LOCAL_NODE_OK` and `CPE_NODE_OK`.

### 5.3 `/etc/wifibroadcast.cfg` — cluster and local node

Requirements for the cluster section:

- `server_address` must be the relay LAN address, 10.5.7.100. It is the only address every node
  can reach.
- The CPE610 node is declared at 10.5.7.102 with its monitor interface, `phy0-mon0`.
- A local node entry at `127.0.0.1` is declared when the relay's own USB adapter is to
  participate in the cluster.
- For the receive-only node, `wifi_txpower` is set to `None`, the driver default.

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
cluster SSH. Without the explicit interpreter the execution fails against the node's `ash`
shell and `phy0-mon0` is never created.

**NOTE.** `custom_init_script` is of particular importance on OpenWrt 24.10 and later, where the
radio may not be initialised if it is disabled. See the WFB-NG distributed-operation reference
in Section 3.

### 5.4 Systemd unit `wifibroadcast-cluster@gs.service`

**CAUTION.** Cluster mode must not use `--wlans`. The server reads `[cluster] nodes` from
`/etc/wifibroadcast.cfg`. The unit below is the authoritative service definition for cluster
operation.

```ini
# /etc/systemd/system/wifibroadcast-cluster@.service
[Unit]
Description=WFB-ng CLUSTER server, profile %i
Requires=wifibroadcast.service
ReloadPropagatedFrom=wifibroadcast.service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
# Common environment
EnvironmentFile=/etc/default/wifibroadcast
# Per-profile environment
EnvironmentFile=-/etc/default/wifibroadcast.%i

# Cluster mode reads [cluster] nodes from /etc/wifibroadcast.cfg. Do not add --wlans.
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

# Follow the service log
journalctl -u wifibroadcast-cluster@gs.service -f
```

### 5.5 Per-profile environment file

Systemd units load environment variables per profile. `/etc/default/wifibroadcast.gs` is an
optional file that sets variables for the `gs` profile only — for example, selecting the cluster
mode.

```sh
# /etc/default/wifibroadcast.gs
# Cluster mode: ssh or manual
WFB_CLUSTER_MODE=ssh
```

---

## 6 Troubleshooting

### 6.1 `argument --wlans not allowed with --cluster`

Expected behaviour. In cluster mode `--wlans` is not passed on the server command line. Declare
all node interfaces in `/etc/wifibroadcast.cfg` under `[cluster]`, and start the server through
`wifibroadcast-cluster@gs.service` as specified in Section 5.4.

### 6.2 `Unable to decrypt packet`

Indicates a keypair mismatch between `gs.key` and `drone.key`, or an incorrect peer. Confirm
that `/etc/gs.key` on the relay corresponds to the transmitting station's keypair, and that the
configured channel and bandwidth match on both ends.

### 6.3 `ip: SIOCGIFFLAGS: No such device` on the node

The monitor interface is absent. Confirm that `/usr/sbin/wfb-mon0.sh` exists and is executable
on the node. Where the boot-time service of Section 4.4 is in use, confirm that it is enabled
and completed successfully. Verify with `iw dev`.

In the deployed configuration the interface is created by the relay at cluster start, so this
error is also the expected state of a node that has been rebooted in isolation. Restart
`wifibroadcast-cluster@gs.service` on the relay.

### 6.4 Cluster SSH reports `Permission denied`

Confirm that the relay's `/home/vind-admin/.ssh/wfb_cluster_ed25519.pub` is present in each
node's authorised-keys file, including the local node at `127.0.0.1`. On OpenWrt the file is
`/etc/dropbear/authorized_keys`; on the relay it is `/root/.ssh/authorized_keys`.

### 6.5 Apparent link-quality improvement at MCS 1

A lower MCS index applies more robust modulation and coding, which generally improves effective
link quality and reduces packet loss. Some OSD and telemetry displays report a higher RSSI or
quality figure when the link is neither saturating nor losing frames. MCS is to be treated as a
stability-and-range against throughput control, not as a quality metric in itself. The deployed
value is `mcs_index = 1`.

---

## Appendix A — Quick reference commands

```sh
# Relay: restart the cluster server
sudo systemctl restart wifibroadcast-cluster@gs.service

# Relay: confirm the server is running and nodes have registered
wfb-cli status

# Node: confirm the monitor interface is present
iw dev | grep -A3 phy0-mon0
iw dev phy0-mon0 info
```

---

## Appendix B — Corrections applied to the source document

| Item | Source document | Corrected value |
| --- | --- | --- |
| RF channel | 157 (5785 MHz) | **161 (5805 MHz), HT20** |
| `ssh_key` | `/root/.ssh/wfb_cluster_ed25519` | **`/home/vind-admin/.ssh/wfb_cluster_ed25519`** |
| `custom_init_script` | `/usr/sbin/wfb-mon0.sh` | **`sh /usr/sbin/wfb-mon0.sh`** |
| `api_port` / `stats_port` | 8203 / 8303 in `[cluster]` | **8103 / 8003 in `[gs]`** |
| WFB-NG source | Clone `svpcom/wfb-ng` and copy the recipe | **Official OpenWrt 24.10.4 package feed** |
| Node verification command | `wfb-server --version` | **`opkg list-installed \| grep -i wfb-ng`** — `wfb-server` is not installed on the node |
| Boot-time monitor service | Presented as required | **Not installed; the relay creates the interface at cluster start** |

The addressing plan in this revision (10.5.7.0/24) is already correct and required no
correction. The complete parameter set, with the supporting evidence, is specified in
[`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md).
