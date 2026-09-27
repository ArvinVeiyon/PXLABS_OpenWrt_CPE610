# PXLABS_OpenWrt_CPE610 — Technical Reference

Custom OpenWrt 24.10.4 firmware for the TP-Link CPE610 v2, deployed as the receive node of a
two-node `wifibroadcast-cluster@gs` WFB-NG cluster.

| Field | Value |
| --- | --- |
| Document type | Technical reference |
| Applies to | TP-Link CPE610 v2, OpenWrt 24.10.4 (`r28959-29397011cc`), WFB-NG 25.01-r1 |
| Revision | 1.1 |
| Date | 2026-09-27 |
| Status | Current |
| Authoritative parameter source | [`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md) |

**Precedence.** Where this document and `docs/DEPLOYED_PARAMETERS.md` disagree on a parameter
value, `docs/DEPLOYED_PARAMETERS.md` governs. `config/master.cfg` is the upstream WFB-NG
template and is not the deployed configuration; it is retained for reference and comparison
only.

---

## 1 Scope

This repository contains the package recipes, build configuration, flashable firmware
artifacts and deployment records for the CPE610 v2 receive node. The OpenWrt SDK (3.5 GB) and
ImageBuilder (1.2 GB) are unmodified upstream downloads and are not committed; Section 7
specifies their retrieval.

This repository covers the OpenWrt node only. Relay-side subject matter — MAVLink routing,
QGroundControl behaviour, flight-mode selection and the relay's own service configuration — is
maintained in the `Relay_Station_Pxlabs` repository and is out of scope here.

---

## 2 System description

### 2.1 Role

The CPE610 is not a standalone receiver. It is a cluster node. The relay (`vind-rly`,
10.5.7.100) executes `wfb-server --profiles gs --cluster ssh` and drives two radio nodes over
SSH: its own RTL8812EU adapter, and this unit's `phy0-mon0` monitor interface at 10.5.7.102.

```
        Drone (WFB-NG TX)
               │  5 GHz raw Wi-Fi, ch 161 / 5805 MHz / HT20
       ┌───────┴────────┐
       ▼                ▼
  CPE610 v2        RTL8812EU
  phy0-mon0        wlx00c0cab6db3b
  (ath9k, RX)      (relay's own adapter)
  10.5.7.102            │
       │  Ethernet      │
       └───────┬────────┘
               ▼
      Relay  10.5.7.100  ── wfb-server --cluster ssh
               │
               ▼  10.5.6.0/24
      Laptop / ground station  10.5.6.50
```

### 2.2 Design characteristics

The following two characteristics are intended behaviour, not faults. Both are frequently
misread as defects.

**No network egress.** The unit has a single radio and therefore cannot operate as a station
and a channel-161 monitor concurrently. `radio0` is disabled, with the consequence that no
default route and no package feed are available. Software must be transferred as an `.ipk`
over Ethernet.

**Receive-only in practice.** The ath9k driver reports absolute dBm and supplies no noise
figure, so reported SNR is 0. The relay's RTL8812EU reports `rssi_avg` in the range +14 to
+16. Evaluated against `tx_sel_rssi_delta = 3`, the relay adapter consistently wins transmit
arbitration. This is a chipset reporting difference. The node's receive contribution is
measured and material: 220 packets from the node against 233 from the relay adapter over the
same interval, with `dec_err: [0, 0]`.

### 2.3 Build matrix

| Item | Value |
| --- | --- |
| Board | TP-Link CPE610 v2 (Atheros AR9344, 8 MB flash, 64 MB RAM) |
| OpenWrt release | 24.10.4 (`r28959-29397011cc`) |
| Target / subtarget | `ath79` / `generic` |
| Package architecture | `mips_24kc` |
| Toolchain | `gcc-13.3.0`, musl |
| Kernel | 6.6.110 (`35ef4dd36891d37023436baa842fa311`) |
| Radio driver | ath9k (`kmod-ath9k`) |
| WFB-NG in the image and on the device | 25.01-r1 |

---

## 3 Provenance of WFB-NG 25.01-r1

WFB-NG is not built from a recipe in this repository. Versions 25.01-r1 of `wfb-ng` and
`wfb-ng-tun` are published in the official OpenWrt 24.10.4 package feed and were retrieved
from it by the ImageBuilder:

```
https://downloads.openwrt.org/releases/24.10.4/packages/mips_24kc/packages
```

That feed is already declared as `openwrt_packages` in
`config/imagebuilder-repositories.conf`. Consequently the build procedure in Section 7 is
complete and self-contained; no local WFB-NG recipe is required.

Substantiating evidence:

| Evidence | Finding |
| --- | --- |
| Package control metadata | `Source: feeds/packages/net/wfb-ng` — the OpenWrt packages feed |
| ImageBuilder download cache | Holds `wfb-ng_25.01-r1_mips_24kc.ipk` (`71e4fd95…`) and `wfb-ng-tun_25.01-r1_mips_24kc.ipk` (`905a0269…`) |
| Cached feed index | The ImageBuilder's own copy of the official index lists those identical SHA-256 values |

**Limitation on bit-exact reproduction.** The upstream feed has since rebuilt 25.01-r1 and now
publishes different checksums (`ab2c7d26…` and `f2cf58ac…`) under the same version string. A
rebuild therefore yields a functionally equivalent image but not a byte-identical one. This is
an upstream packaging matter and requires no action in this repository.

### 3.1 Superseded 24.9.7-r2 artifacts

`package/wfb-ng/`, `package/wfb-ng-full/` and `packages/ipk/*_24.9.7-r2_*.ipk` are the
remnants of an earlier approach that compiled WFB-NG from `svpcom/wfb-ng@3a05304` in the SDK.
That approach was abandoned once the package was found in the official feed. These artifacts
did not contribute to the committed image, as demonstrated by two facts:

- The `.ipk` files were staged in the ImageBuilder's `packages-local/` directory, whose index
  file `Packages` is zero bytes — an empty index, from which nothing can be resolved.
- `repositories.conf` declares the local repository as `file:packages`, not `packages-local`.

These artifacts are retained for historical traceability and are clearly marked as superseded.
They must not be used as a build input.

---

## 4 Repository layout

```
package/                        Superseded WFB-NG package recipes (24.9.7 — see §3.1)
  wfb-ng/                         base build: wfb_rx / wfb_tx binaries plus wfb-ng-tun
  wfb-ng-full/                    full build: adds the Python stack, wfb-server, wfb_keygen
config/
  sdk.config                      SDK .config used for the superseded .ipk build
  sdk-feeds.conf.default          feed revisions the SDK was pinned to
  imagebuilder.config             ImageBuilder .config used to build the images
  imagebuilder-repositories.conf  ImageBuilder package feeds — supplies WFB-NG 25.01-r1
  master.cfg                      Upstream WFB-NG template; NOT the deployed configuration
images/
  custom/                         PXLABS images with WFB-NG included, plus manifest, SBOM, checksums
  stock/                          Unmodified OpenWrt 24.10.4 release images, retained for recovery
packages/ipk/                     Superseded WFB-NG .ipk artifacts (24.9.7-r2 — see §3.1)
stock-firmware/                   TP-Link vendor configuration backup taken from the unit
deployment/                       Records of the running node, captured 2026-09-26
docs/
  DEPLOYED_PARAMETERS.md          Authoritative parameter reference — consult first
  *_Deployment_Guide.md           Installation and commissioning manuals
  *_Deployment_Guide*.docx        Source Word documents, retained unaltered
```

### 4.1 `package/wfb-ng` compared with `package/wfb-ng-full`

The two recipes are distinct, not duplicates. Both are superseded per Section 3.1; the
distinction is documented because it governs which package set a future build should select.

| Recipe | Contents | Dependencies | Notes |
| --- | --- | --- | --- |
| `wfb-ng` | `wfb_rx`, `wfb_tx`, `wfb_tun`; builds `wfb-ng` and `wfb-ng-tun` | `libpcap`, `libsodium`, `libstdcpp` | The package set the node runs. No `wfb-server` is present on the CPE610. |
| `wfb-ng-full` | Adds the Python control plane, `wfb-server` as cluster manager, `wfb_tx_cmd`, `wfb_keygen`; reads `/etc/wifibroadcast.cfg` | `python3-twisted`, `pyserial`, `msgpack`, `jinja2`, `pyroute2`, `bash`, `iw`, `openssh-client` | Declares `CONFLICTS:=wfb-ng`. Substantially larger; assess against the CPE610 flash budget before selecting. |

The ImageBuilder's copy of the `wfb-ng` recipe (`package/network/utils/wfb-ng/`) is
byte-identical to the SDK's and is therefore committed once.

---

## 5 Justification for custom firmware

The device's `/overlay` has approximately 450 KB free, while `libstdcpp6` alone requires
approximately 2 MB:

```
verify_pkg_installable: Only have 480kb available on filesystem /overlay
pkg libstdcpp6 needs 2070
```

Removing packages does not recover sufficient space, a squashfs `/overlay` cannot be resized,
and external storage is not dependable on this platform. Installation by `opkg install wfb-ng`
is therefore not achievable on a CPE610 under any configuration. WFB-NG must be incorporated
into the firmware image at build time. This constraint is the reason this repository exists.

---

## 6 Firmware images

`images/custom/` is produced by the ImageBuilder from `config/imagebuilder.config` and
`config/imagebuilder-repositories.conf`, with WFB-NG resolved from the official OpenWrt feed.

| File | Size (bytes) | MD5 |
| --- | --- | --- |
| `custom/…-squashfs-factory.bin` | 6,964,588 | `baf447c623541396a9c1329a68998974` |
| `custom/…-squashfs-sysupgrade.bin` | 7,804,077 | `2d83bb2a755b3be6571ea1395ad35f8d` |
| `stock/…-squashfs-factory.bin` | 6,571,372 | `8f833c9ed9eccf7c2682ad2617447e53` |
| `stock/…-squashfs-sysupgrade.bin` | 7,803,579 | `248d93c93ae6027d2805f35e493fae9b` |

SHA-256 values for the custom pair are in `images/custom/sha256sums`, the package list in
`images/custom/…manifest`, and the software bill of materials in `…bom.cdx.json`.

### 6.1 Correspondence with the deployed unit

The committed custom image is the deployed firmware. Its manifest and
`deployment/packages-installed.txt` share 118 packages at identical versions. The device
carries two additional packages, `ethtool` and `tcpdump`, incorporated in a marginally later
build. The image is to be described as matching deployment, not as approximating it.

### 6.2 Flashing

| Starting state | Image to use | Command |
| --- | --- | --- |
| TP-Link Pharos vendor firmware | **factory** | Vendor web interface |
| Existing OpenWrt installation | **sysupgrade** | `sysupgrade -n <image>` |

The `-n` flag discards the existing configuration. It is required when the WFB-NG layout has
changed.

`stock-firmware/CPE610-v2_stock_config.bin` is the configuration backup taken from the unit
before conversion. It is to be retained: it is the only path back to the vendor
configuration.

---

## 7 Build reproduction

Neither upstream tree is committed; both must be retrieved. Review the reproduction limitation
in Section 3 before relying on output checksums.

### 7.1 Firmware image (ImageBuilder)

This procedure is complete. It requires no local WFB-NG recipe and no locally built `.ipk`
files.

```bash
cd ~/owrt
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
cd openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64

cp /path/to/PXLABS_OpenWrt_CPE610/config/imagebuilder.config              .config
cp /path/to/PXLABS_OpenWrt_CPE610/config/imagebuilder-repositories.conf   repositories.conf

make image PROFILE=tplink_cpe610-v2 \
     PACKAGES="wfb-ng wfb-ng-tun iw ca-bundle -luci -uhttpd -uhttpd-mod-ubus"
```

Output is written to `bin/targets/ath79/generic/`.

The package selection above is reconstructed from `images/custom/…manifest`, which contains
`wfb-ng`, `wfb-ng-tun`, `iw`, `ca-bundle`, `kmod-tun`, `libsodium` and `libpcap1`, and
contains neither `luci` nor `uhttpd`. `kmod-tun`, `libsodium` and `libpcap1` are resolved as
dependencies and need not be listed explicitly.

**No `FILES=` overlay was used.** The ImageBuilder tree contains no `files/` directory, and
neither `/usr/sbin/wfb-mon0.sh` nor `/etc/init.d/wfb-mon0` is present in the built root
filesystem. This is consistent with the deployment records: the monitor-interface script was
installed on the unit separately and is not part of the image. See Section 8.

Image checksums are not bit-reproducible across ImageBuilder extractions because `key-build`,
the package-signing key, is regenerated on each extraction. That key is excluded from version
control deliberately.

### 7.2 Building WFB-NG from source (not required)

This procedure is recorded for completeness only. It reproduces the superseded 24.9.7-r2
artifacts described in Section 3.1 and does not reproduce the deployed image.

```bash
cd ~/owrt
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
cd openwrt-sdk-24.10.4-ath79-generic_gcc-13.3.0_musl.Linux-x86_64

cp -r /path/to/PXLABS_OpenWrt_CPE610/package/wfb-ng      package/
cp -r /path/to/PXLABS_OpenWrt_CPE610/package/wfb-ng-full package/
cp /path/to/PXLABS_OpenWrt_CPE610/config/sdk-feeds.conf.default feeds.conf.default

./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/PXLABS_OpenWrt_CPE610/config/sdk.config .config
make defconfig
make package/wfb-ng/compile V=s          # or package/wfb-ng-full/compile
```

Output is written to `bin/packages/mips_24kc/base/`.

The recipe retrieves WFB-NG from `https://github.com/svpcom/wfb-ng.git` at commit `3a05304`,
so a local clone is not required. The clone at `~/owrt/wfb-ng` is an unmodified `master` at
`109e1ad` (2025-12-20), 97 commits ahead of the pinned revision, and has never been built.

To adopt a newer WFB-NG than the feed provides — for example 25.4.27, which the relay and
drone already run — build it for `mips_24kc` on an x86 host with network access and transfer
the resulting `.ipk` to the node over Ethernet.

---

## 8 Runtime configuration

The node holds no `wifibroadcast.cfg` of its own. It runs the base `wfb-ng` and `wfb-ng-tun`
pair and is driven entirely over cluster SSH from the relay. The relay's
`/etc/wifibroadcast.cfg` is therefore the sole location in which the link parameters exist. A
captured copy is preserved at
[`deployment/wifibroadcast.cfg.relay`](deployment/wifibroadcast.cfg.relay); the reconciled
values are specified in [`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md).

`config/master.cfg` is the upstream template, retained for reference and comparison. It must
not be deployed.

**Monitor interface creation.** `phy0-mon0` is created by the relay at each cluster start
through `custom_init_script`, not at node boot. `deployment/etc/rc.local` is unmodified and no
`/etc/init.d/wfb-mon0` service is present, contrary to the instruction given in both
deployment manuals. A node rebooted in isolation has no monitor interface until the relay's
cluster service is restarted.

---

## 9 Security

No cryptographic material is stored in this repository, and none is to be added. `*.key` is
excluded by `.gitignore`, and the residential SSID pre-shared key in
`deployment/etc/config/wireless` is redacted. Generate WFB-NG keypairs with `wfb_keygen`, from
the `wfb-ng-full` package, and distribute them out of band.

**Open finding, tracked outside this repository.** The public `ArvinVeiyon/Relay_Station_Pxlabs`
repository — the upstream source of the `deployment/` records — retains genuine `gs.key`,
`drone.key` and `wfb_cluster_ed25519` on its default branch, retrievable without
authentication. Remediation requires key rotation together with a history purge; a deletion
commit is not sufficient. Details are recorded in
[`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md#10-security).

---

## 10 Exclusions

| Excluded item | Size | Reason |
| --- | --- | --- |
| `openwrt-sdk-24.10.4-…/` | 3.5 GB | Upstream; retrieve per Section 7.2 |
| `openwrt-imagebuilder-24.10.4-…/` | 1.2 GB | Upstream; retrieve per Section 7.1 |
| `sdk.tar.zst` | 199 MB | Exceeds the GitHub 100 MB per-file limit |
| `ib.tar.zst` | 103 MB | Exceeds the GitHub 100 MB per-file limit |
| `~/owrt/wfb-ng/` | 6 MB | Unmodified clone of `svpcom/wfb-ng`; pinned by commit in the recipe |
| `dl/` archives | 425 MB | Upstream source archives, re-retrieved by the build |
| `key-build*`, `keys/` | — | Regenerated on each extraction; signing keys are not version-controlled |
