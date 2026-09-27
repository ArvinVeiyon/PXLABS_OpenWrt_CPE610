# CPE610 v2 Receive Node — Operations and Maintenance Manual

| Field | Value |
| --- | --- |
| Document type | Operations and maintenance manual |
| Applies to | TP-Link CPE610 v2 receive node, OpenWrt 24.10.4, WFB-NG 25.01-r1, release `v24.10.4-pxlabs-cpe610-r1` |
| Revision | 1.0 |
| Date | 2026-09-27 |
| Status | Current |

**Scope.** This manual covers the node in service: routine checks, logging, start and stop
procedures, fault isolation, recovery and rollback, and provisioning a replacement unit. It
assumes the node has already been built, flashed and commissioned per the installation manual.

**Precedence.** Parameter values are specified in
[`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md), which governs wherever this manual and that
document disagree.

**Boundary.** Relay-side behaviour beyond the cluster service — MAVLink routing to
QGroundControl, flight-mode selection, the hop that forwards `gs_mavlink` onward to the ground
station — is out of scope here and is maintained in the `Relay_Station_Pxlabs` repository. A
fault isolated to that hop by Section 7 is handed over, not diagnosed here.

---

## 1 Applicable documents

| Document | Use |
| --- | --- |
| [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) | Authoritative parameter values and expected readings |
| [`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md) | Installation and commissioning procedure |
| [`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md) | Cluster configuration, systemd unit, cluster troubleshooting |
| [`DOCUMENT_REGISTER.md`](DOCUMENT_REGISTER.md) | Document revisions, precedence, and the revision each release shipped |
| `../CHANGELOG.md` | What changed in each release, and the items carried forward |
| `../README.md` | Build reproduction, image records, repository layout |
| `../deployment/README.md` | The configuration in force on the node, as captured |

---

## 2 The dependency that governs all node operations

**`phy0-mon0` is created by the relay, not by the node.** The monitor interface is established at
each cluster start through `custom_init_script`. The node runs no service that creates it: its
`/etc/rc.local` is unmodified and no `/etc/init.d/wfb-mon0` is installed.

Two consequences govern every procedure in this manual:

1. **A node restarted on its own has no monitor interface, and no amount of waiting will create
   one.** The relay's cluster service must be restarted afterwards.
2. **A node that appears dead may be a node with no monitor interface.** Check for the interface
   before concluding the unit has failed.

Section 6 states the restart order that follows from this. See `DEPLOYED_PARAMETERS.md` §7.

---

## 3 Normal indications

### 3.1 Physical

| Indicator | Normal condition | Meaning |
| --- | --- | --- |
| LAN LED (green) | Illuminated, flickering with traffic | `eth0` link up with activity. Configured as `trigger netdev`, `mode link tx rx` on `eth0`. |
| LAN LED | Dark | No Ethernet link. Cable, connector or switch fault — check before anything else. |
| Wireless LEDs | Not meaningful | `radio0` is disabled by design; the monitor interface does not drive the managed-radio indicators. |

### 3.2 Logical

| Check | Normal result |
| --- | --- |
| `ip -4 addr show br-lan` | 10.5.7.102/24 |
| `iw dev` | `phy0-mon0` present, `type monitor` |
| `iw dev phy0-mon0 info` | Channel 161, 5805 MHz, width 20 MHz |
| `ip link show phy0-mon0` | State `UP` |
| `uci get wireless.radio0.disabled` | `1` |
| `ls /usr/bin/wfb_*` | `wfb_rx`, `wfb_tx`, `wfb_tun` |
| No default route | Expected. The node has no internet by design. |

### 3.3 Expected anomalies — not faults

These readings look wrong and are correct. Do not raise them as defects.

| Observation | Explanation |
| --- | --- |
| Node SNR reads 0 | ath9k reports absolute dBm and supplies no noise figure. See `DEPLOYED_PARAMETERS.md` §6.2. |
| Node never wins transmit arbitration | Chipset reporting difference against `tx_sel_rssi_delta = 3`. The node is a receive contributor. |
| Node RSSI around −23 to −21 dBm | True dBm from ath9k, against the relay adapter's `rssi_avg` of +14 to +16. The two scales are not comparable. |
| `wfb-server` absent from the node | Correct. The node runs the base package pair and is driven by the relay. |
| No default route, `opkg update` fails | Correct. No feed, no egress. |
| `phy0-sta0` absent | Residual `sta` configuration for SSID `Nilan_5GHz` is never applied. |
| Clock wrong, log timestamps implausible | See Section 4.3. |

---

## 4 Logging

### 4.1 Node logging is volatile and small

The node runs `logd` with `option log_size '128'` — a **128 KiB in-memory ring buffer**. There is
no persistent log.

**CAUTION.** Everything in the node's log is lost on reboot, and a busy period overwrites earlier
entries. **Capture the log before restarting a node you are investigating.** A reboot performed
first destroys the only evidence.

```sh
logread                      # whole buffer
logread -f                   # follow
logread | tail -n 100        # recent entries
logread -e wfb               # filter
dmesg | tail -n 50           # kernel ring buffer, also volatile
```

### 4.2 Relay logging is the authoritative record

The relay drives the cluster, so relay logs carry the session history the node cannot.

```sh
journalctl -u wifibroadcast-cluster@gs.service -n 200
journalctl -u wifibroadcast-cluster@gs.service -f
journalctl -u wifibroadcast-cluster@gs.service --since "1 hour ago"
journalctl -u wifibroadcast.service -n 100
```

### 4.3 Node timestamps are not reliable

The node has NTP **configured but unreachable**: `/etc/config/system` enables the `ntp` client
against `*.openwrt.pool.ntp.org`, while the node has no default route and no egress. The clock
therefore never synchronises and node log timestamps cannot be correlated against relay logs by
absolute time.

Correlate by event order and by relay timestamps instead. The relay is the time reference.

**NOTE — timezone notation.** `/etc/config/system` carries `option timezone 'IST-5:30'` with
`zonename 'Asia/Kolkata'`. The POSIX sign convention is inverted, so `IST-5:30` denotes UTC+5:30
and is correct. Do not "fix" the sign.

### 4.4 Evidence set for a fault report

Collect all of the following, in this order, **before** restarting anything:

```sh
# On the node
logread > /tmp/node-logread.txt
dmesg > /tmp/node-dmesg.txt
iw dev > /tmp/node-iwdev.txt
iw dev phy0-mon0 info >> /tmp/node-iwdev.txt
ip -4 addr show > /tmp/node-addr.txt
ip link show >> /tmp/node-addr.txt
opkg list-installed > /tmp/node-packages.txt
cat /etc/openwrt_release > /tmp/node-release.txt

# Then copy them off, from the relay
scp root@10.5.7.102:/tmp/node-*.txt ./

# On the relay
journalctl -u wifibroadcast-cluster@gs.service -n 500 > relay-cluster.log
cp /etc/wifibroadcast.cfg relay-wifibroadcast.cfg
```

---

## 5 Routine checks

No routine maintenance is required by the hardware. The checks below confirm the link is
performing and catch degradation before it becomes a loss of service.

### 5.1 Before each operating session

| # | Check | Expected |
| --- | --- | --- |
| 1 | LAN LED on the node | Illuminated |
| 2 | `ping -c 3 10.5.7.102` from the relay | 0% loss |
| 3 | `systemctl is-active wifibroadcast-cluster@gs.service` | `active` |
| 4 | Monitor interface present and on channel 161 | Per Section 3.2 |
| 5 | Both cluster nodes registered, non-zero received count from each | Per Section 5.2 |

### 5.2 Link performance

Statistics are read on the relay, from the `gs` profile — by the WFB-NG CLI for that profile, or
programmatically on `stats_port` 8003 and `api_port` 8103 (see `DEPLOYED_PARAMETERS.md` §4).

| Quantity | Expected | Investigate when |
| --- | --- | --- |
| Received packets, node | Non-zero, comparable order to the relay adapter — 220 against 233 was measured at commissioning | Zero, or an order of magnitude below the relay adapter |
| `dec_err` | `[0, 0]` | Any sustained non-zero value |
| Node RSSI | Approximately −23 to −21 dBm | Consistently weaker than about −30 dBm |
| Transmit selection | Relay adapter wins | Not a fault in any case; see Section 3.3 |

A node contribution that has fallen to zero while the relay adapter still receives indicates a
node-side fault. Start at Section 7.2, symptom A.

### 5.3 Thermal

WFB-NG samples node temperature every 2 seconds (`temp_measurement_interval = 2`) and warns at
60 °C (`temp_overheat_warning = 60`). The warning appears in the relay's cluster log.

On an overheat warning: confirm the enclosure is ventilated and not in direct sun, and confirm the
mounting has not trapped the unit against a heat source. The CPE610 is a sealed outdoor unit with
no serviceable cooling.

### 5.4 Periodic

| Interval | Action |
| --- | --- |
| Each session | Section 5.1 |
| After any node restart | Confirm the relay cluster service was restarted afterwards — Section 6 |
| After any configuration change on the relay | Re-run the commissioning acceptance checks, installation manual §22 |
| After any change to the deployed configuration | Update `DEPLOYED_PARAMETERS.md` and the `deployment/` records |
| Annually, or after any enclosure disturbance | Inspect the Ethernet gland and connector for water ingress |

**No software update is possible in place.** The node has no package feed. Any software change
requires building a new image and reflashing — see the installation manual, Parts II and III.

---

## 6 Start, stop and restart

### 6.1 Restart order

| Action taken | Required follow-up |
| --- | --- |
| Node rebooted or power-cycled | **Restart `wifibroadcast-cluster@gs.service` on the relay.** The node has no monitor interface until this is done. |
| Relay cluster service restarted | None. The service recreates `phy0-mon0` on the node over cluster SSH. |
| Relay rebooted | None beyond confirming the service came up. |
| Both restarted | Bring the node up first, confirm it is reachable at 10.5.7.102, then start the relay service. |

### 6.2 Node restart

```sh
# From the relay
ssh root@10.5.7.102 'reboot'

# Wait for the unit to return, then confirm reachability
ping -c 3 10.5.7.102

# REQUIRED: recreate the monitor interface
sudo systemctl restart wifibroadcast-cluster@gs.service

# Confirm
ssh root@10.5.7.102 'iw dev | grep -A3 phy0-mon0'
```

Allow approximately 60 seconds for the node to boot.

### 6.3 Relay cluster restart

```sh
sudo systemctl restart wifibroadcast-cluster@gs.service
systemctl status wifibroadcast-cluster@gs.service
journalctl -u wifibroadcast-cluster@gs.service -n 50
```

### 6.4 Planned shutdown

```sh
ssh root@10.5.7.102 'poweroff'
```

Wait for the LAN LED to extinguish before removing power. The node carries no state that must be
flushed, but an abrupt cut during a write to the overlay risks the configuration partition.

### 6.5 Stopping the link without stopping the node

Stop the cluster service on the relay. The node retains its monitor interface until the service's
stop action removes it, and requires no separate command.

```sh
sudo systemctl stop wifibroadcast-cluster@gs.service
```

---

## 7 Fault isolation

### 7.1 Symptom index

| Symptom | Start at |
| --- | --- |
| No video at the ground station | 7.2 D |
| Node contributes no received packets, relay adapter still receives | 7.2 A |
| Node unreachable over Ethernet | 7.2 B |
| Cluster service fails to start, or reports an error at start | 7.2 C |
| `dec_err` non-zero and rising | 7.2 E |
| Both nodes receive nothing | 7.2 F |
| Overheat warning | 5.3 |

### 7.2 Procedures

**A — Node contributes nothing; relay adapter still receives**

1. Confirm the monitor interface exists: `ssh root@10.5.7.102 'iw dev'`. Absent → the cluster
   service has not created it. Restart the service per 6.3. This is the most common cause and is
   the expected state after an isolated node reboot.
2. Confirm the channel: `iw dev phy0-mon0 info`. Must read channel 161, width 20 MHz. A different
   channel means `wfb-mon0.sh` was altered or the relay's `[cluster]` channel disagrees.
3. Confirm the script is present and executable: `ls -l /usr/sbin/wfb-mon0.sh`. Missing → the node
   has been reflashed without reinstalling it; see installation manual §15.
4. Confirm the interface is up: `ip link show phy0-mon0`.
5. Capture the evidence set per 4.4, then restart the node per 6.2.

**B — Node unreachable over Ethernet**

1. LAN LED dark → cable, connector or switch. Confirm at both ends. Water ingress at the gland is
   a known failure mode for outdoor units.
2. LED lit but no reply to ping → confirm the relay's own LAN address is 10.5.7.100/24 and that
   the relay is not routing 10.5.7.0/24 elsewhere.
3. Confirm the node's address has not been reset to the OpenWrt default: attempt
   `ping 192.168.1.1`. A response means the configuration was lost — most likely a `sysupgrade`
   applied with `-n`. Reapply Section 13 of the installation manual.
4. No response on either address → the unit requires physical access. Proceed to Section 8,
   failsafe mode.

**C — Cluster service fails at start**

Read the relay log first: `journalctl -u wifibroadcast-cluster@gs.service -n 100`.

| Log content | Cause and action |
| --- | --- |
| `ash: /bin/bash: not found` | The `/bin/bash` symlink is absent on the node. Installation manual §17. |
| `Permission denied` | Cluster SSH key not authorised. Confirm the public key is in the node's `/etc/dropbear/authorized_keys`. Installation manual §19. |
| `argument --wlans not allowed with --cluster` | The service is passing `--wlans`. Use the unit as specified in the cluster manual §5.4. |
| `ip: SIOCGIFFLAGS: No such device` | The monitor interface was not created. Confirm `custom_init_script` carries the explicit `sh` prefix — `DEPLOYED_PARAMETERS.md` §1.1. |
| Node unreachable | Symptom B. |

**D — No video at the ground station**

Isolate in this order, stopping at the first failure:

1. Is the cluster service active and are both nodes registered? No → symptom C.
2. Is either node receiving packets? Neither → symptom F. Node only → the link is up and the
   fault is downstream; continue.
3. Is `dec_err` clean? No → symptom E.
4. Is the relay forwarding to the ground station at 10.5.6.50:5600? The deployed peer is
   `gs_video peer connect://10.5.6.50:5600` — see `DEPLOYED_PARAMETERS.md` §5.
5. Reaching this step means the link and the node are performing and the fault is in the relay's
   onward path to the ground station. **That hop is out of scope for this repository** — hand over
   to `Relay_Station_Pxlabs`.

**E — `dec_err` non-zero and rising**

Decode errors indicate the received frames are not decrypting or not reconstructing.

1. Keypair mismatch is the usual cause. Confirm the relay's `gs.key` corresponds to the
   transmitting station's keypair. The node holds no key and cannot cause this.
2. Confirm channel and bandwidth agree at both ends — channel 161, HT20.
3. Confirm the FEC settings match the transmitter: video `k=8 n=12`. See
   `DEPLOYED_PARAMETERS.md` §5.
4. A rising error rate with correct keys and matching channel indicates interference or a
   marginal link. Compare the two nodes' error rates: errors on both point to the RF environment
   or the transmitter, errors on one point to that receiver.

**F — Neither node receives anything**

The node is not implicated when both receivers are silent. Check, in order: that the drone is
transmitting; that the drone is on channel 161; that the regulatory domain has not restricted the
channel; and that the transmitting keypair matches. The node's own configuration cannot produce
this symptom.

---

## 8 Diagnostic tools on the node

The deployed unit carries two diagnostic packages that are **not** in the committed image —
`tcpdump` 4.99.5-r1 and `ethtool` 6.11-r1 — incorporated in a marginally later build. They are
available on the running unit and are worth knowing about, because the node has no package feed
and nothing further can be added without reflashing.

| Tool | Use |
| --- | --- |
| `tcpdump` | Confirm frames are arriving. `tcpdump -i phy0-mon0 -c 20` shows raw captures on the monitor interface; `tcpdump -i br-lan -n port 11000` shows cluster traffic to the relay. |
| `ethtool` | Confirm Ethernet link speed and duplex: `ethtool eth0`. Use when the LAN LED is lit but throughput is poor. |
| `iw` | Interface state, channel, regulatory domain: `iw dev`, `iw dev phy0-mon0 info`, `iw reg get`. |
| `iwinfo` | Summary view: `iwinfo phy0-mon0 info`. |
| `logread`, `dmesg` | Section 4.1. |

**NOTE.** A replacement unit flashed from the committed image will **not** have `tcpdump` or
`ethtool`. To retain them, add both to the `PACKAGES` list when building — installation manual
§7 — or carry the `.ipk` files in over Ethernet.

### 8.1 Failsafe mode — physical access required

Where the node is unreachable on both its configured and default addresses, OpenWrt failsafe mode
provides a recovery shell. This is the standard OpenWrt procedure: power on the unit and press the
reset button when the status LED begins to flash, which brings the device up at **192.168.1.1**
with no configuration applied and only a ramdisk mounted. Connect directly by Ethernet with a
static address on 192.168.1.0/24, then:

```sh
# From the connected host
telnet 192.168.1.1        # or: ssh root@192.168.1.1

# On the device, to make the overlay writable
mount_root

# Then either repair the configuration, or reset it completely
firstboot && reboot       # erases the overlay, returning to the flashed image defaults
```

**CAUTION — not validated on this unit.** The procedure above is the documented OpenWrt behaviour
and has not been exercised on this node. Validate it on a spare CPE610 v2 before relying on it in
the field, and note that `firstboot` discards the node's address and the monitor script, both of
which must then be reinstated per the installation manual, Sections 13 and 15.

---

## 9 Recovery and rollback

### 9.1 Selecting the correct action

| Situation | Action | Section |
| --- | --- | --- |
| Configuration damaged, firmware sound | Restore configuration | 10 |
| Current release misbehaving; a previous release was sound | Roll back to that release | 9.2 |
| Firmware suspect, same release to be reinstated | Reflash the current release | 9.3 |
| WFB-NG to be removed, plain OpenWrt wanted | Reflash unmodified OpenWrt | 9.4 |
| Unreachable, physical access available | Failsafe mode | 8.1 |
| Unit to be returned to vendor firmware | See 9.5 | 9.5 |

### 9.2 Roll back to a previous release

Released images are committed under `images/custom/` at each release tag. Because tags are frozen,
a tag's images are exactly what was released.

**NOTE.** The images are **not** attached as GitHub release assets. Retrieve them from git at the
tag, as below, or from the release's source archive. The extraction command in this section was
verified against release r1: the recovered file's SHA-256 matched the released checksum exactly.

```sh
cd /home/pxlabs/PXLABS_OpenWrt_CPE610

# List available releases
git tag -l

# Recover the images from a specific release without disturbing the working tree
git show v24.10.4-pxlabs-cpe610-r1:images/custom/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin > /tmp/rollback-sysupgrade.bin

# Verify against the checksum recorded in that release
git show v24.10.4-pxlabs-cpe610-r1:images/custom/sha256sums
sha256sum /tmp/rollback-sysupgrade.bin

# Apply
scp /tmp/rollback-sysupgrade.bin root@10.5.7.102:/tmp/
ssh root@10.5.7.102 'sysupgrade -n /tmp/rollback-sysupgrade.bin'
```

`-n` discards the existing configuration. Reinstate the node configuration per installation manual
Sections 13 to 17 afterwards, then restart the relay cluster service.

Release `v24.10.4-pxlabs-cpe610-r1` sysupgrade SHA-256:
`81d0090aac913561441014d54b0555ec595789f647b8e891496d75250eb4407d`

### 9.3 Reflash the current release

As 9.2, using the images in the working tree at `images/custom/`. Verify against
`images/custom/sha256sums` before flashing.

### 9.4 Reflash unmodified OpenWrt

`images/stock/` holds the unmodified OpenWrt 24.10.4 release images. Flashing these removes
WFB-NG; the node then has no receive capability until a PXLABS image is reapplied. Use this only
to establish a known-good baseline when diagnosing whether a fault originates in the custom
image.

```sh
scp images/stock/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin root@10.5.7.102:/tmp/
ssh root@10.5.7.102 'sysupgrade -n /tmp/openwrt-24.10.4-ath79-generic-tplink_cpe610-v2-squashfs-sysupgrade.bin'
```

`images/stock/` carries no checksum file of its own. The values below were computed from the
committed images; verify against them before flashing.

| Stock image | SHA-256 |
| --- | --- |
| `…-squashfs-factory.bin` | `f84d7a9b86d66ec4d95d85f0b3b41cb722a1b4080f6004ea78ee9f3a5fbbce4f` |
| `…-squashfs-sysupgrade.bin` | `144fd0d1d483ea8ef3b9cd97af8dbe60431f35f813d0e3bafae71e0fdeaf2f97` |

### 9.5 Return to vendor firmware

**The TP-Link Pharos vendor firmware image is not held in this repository.** Returning the unit to
vendor firmware requires that image, obtained from TP-Link for the CPE610 v2 hardware revision,
together with `stock-firmware/CPE610-v2_stock_config.bin`, which is the vendor configuration
backup taken from this unit before conversion.

**CAUTION.** The exact reversion procedure has not been performed on this unit and is therefore
not specified here. Reverting an ath79 TP-Link device from OpenWrt to vendor firmware generally
requires the bootloader's TFTP recovery path rather than `sysupgrade`, and an incorrect image will
brick the unit. Establish the procedure against the vendor documentation for this hardware
revision, and on a spare unit, before attempting it on an in-service node.

---

## 10 Configuration backup and restore

The node's configuration is small and is fully specified by the installation manual. A backup is
nonetheless faster than reconstruction.

```sh
# Back up, from the relay
ssh root@10.5.7.102 'sysupgrade -b /tmp/node-config.tar.gz'
scp root@10.5.7.102:/tmp/node-config.tar.gz ./node-config-$(date +%F).tar.gz

# Restore
scp node-config-<date>.tar.gz root@10.5.7.102:/tmp/
ssh root@10.5.7.102 'sysupgrade -r /tmp/node-config-<date>.tar.gz && reboot'
```

**NOTE.** `sysupgrade -b` captures `/etc` only. It does **not** capture `/usr/sbin/wfb-mon0.sh`,
which lives outside the configuration set. Reinstate that script separately per installation
manual §15. The reference copy is at `../deployment/usr/sbin/wfb-mon0.sh`.

**Records.** `../deployment/` holds the configuration as captured on 2026-09-26 and serves as the
reference for what the node should look like. Where a deployed value is deliberately changed,
update those records and `DEPLOYED_PARAMETERS.md` so the reference stays truthful.

---

## 11 Provisioning a replacement unit

The committed image is reusable across CPE610 v2 units. A replacement is brought into service by
the installation manual, in this order:

| Step | Installation manual section |
| --- | --- |
| 1. Flash the release image — factory from vendor firmware, sysupgrade from OpenWrt | §11 |
| 2. Verify the installation | §12 |
| 3. Set the LAN address to 10.5.7.102/24 | §13 |
| 4. Disable managed wireless | §14 |
| 5. Install `/usr/sbin/wfb-mon0.sh` | §15 |
| 6. Create the `/bin/bash` symlink | §17 |
| 7. Authorise the relay's cluster SSH key | §19.4 |
| 8. Restart the relay cluster service and run the acceptance checks | §21, §22 |

No relay-side change is required provided the replacement takes the same address, 10.5.7.102. The
relay's `[cluster]` node entry is keyed by address.

**Consider adding the boot service.** A replacement unit is a convenient point at which to install
`/etc/init.d/wfb-mon0` (installation manual §16), which makes the node create its own monitor
interface at boot and removes the dependency described in Section 2. This differs from the
currently deployed configuration and is therefore a documented change, not a like-for-like
replacement — record it in Section 12 and update `DEPLOYED_PARAMETERS.md` §7 if adopted.

---

## 12 Maintenance record

Record each intervention. The node carries no self-reported history, its logs do not survive
reboot, and its clock is unsynchronised, so an external record is the only durable account.

| Date | Unit | Action | Firmware / release | Performed by | Verified |
| --- | --- | --- | --- | --- | --- |
| 2026-09-26 | Node 1 | Commissioned; two-node cluster verified end to end | `45f9f72` build, WFB-NG 25.01-r1 | — | 118 packages match image manifest; 220 packets received, `dec_err [0, 0]` |
| 2026-09-27 | — | Release `v24.10.4-pxlabs-cpe610-r1` tagged and published | As above | — | Tag and release verified |

---

## Appendix A — Command quick reference

**On the node**

```sh
iw dev                                   # is phy0-mon0 present?
iw dev phy0-mon0 info                    # channel and width
iw reg get                               # effective regulatory domain
ip -4 addr show br-lan                   # address
ip link show phy0-mon0                   # interface state
logread | tail -n 100                    # recent log (volatile, 128 KiB)
opkg list-installed | grep wfb           # WFB-NG version
cat /etc/openwrt_release                 # release identification
/usr/sbin/wfb-mon0.sh; echo rc=$?        # re-run the monitor setup by hand
tcpdump -i phy0-mon0 -c 20               # are frames arriving?
ethtool eth0                             # Ethernet link speed and duplex
reboot | poweroff                        # restart or shut down
```

**On the relay**

```sh
systemctl status wifibroadcast-cluster@gs.service
systemctl restart wifibroadcast-cluster@gs.service
journalctl -u wifibroadcast-cluster@gs.service -f
ping -c 3 10.5.7.102
ssh -i /home/vind-admin/.ssh/wfb_cluster_ed25519 root@10.5.7.102 'echo CPE_NODE_OK'
```

## Appendix B — Thresholds and expected values

| Quantity | Value | Source |
| --- | --- | --- |
| Node address | 10.5.7.102/24 | `DEPLOYED_PARAMETERS.md` §3.1 |
| Relay cluster address | 10.5.7.100 | §3.1 |
| Ground station | 10.5.6.50 | §3.1 |
| Channel / width | 161, 5805 MHz, HT20 | §2 |
| Effective regulatory domain | `BO` | §2.1 |
| Overheat warning | 60 °C | §2 |
| Temperature sample interval | 2 s | §2 |
| Node RSSI, nominal | −23 to −21 dBm | §6.2 |
| Node SNR | 0 — expected, not a fault | §6.2 |
| `dec_err`, nominal | `[0, 0]` | §6.2 |
| Received packets at commissioning | 220 node / 233 relay adapter | §6.2 |
| Node log buffer | 128 KiB, volatile | This manual, §4.1 |
| Stats / API ports (`gs`) | 8003 / 8103 | §4 |
