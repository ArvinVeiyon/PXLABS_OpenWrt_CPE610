# PXLABS_OpenWrt_CPE610

Custom OpenWrt 24.10.4 firmware for the **TP-Link CPE610 v2** (target `ath79/generic`, arch
`mips_24kc`) with **WFB-NG baked into the image**, deployed as the RX node of a two-node
`wifibroadcast-cluster@gs` cluster.

This repo holds the *sources, build configuration, flashable artifacts and deployment
evidence only*. The OpenWrt SDK (3.5 GB) and ImageBuilder (1.2 GB) are upstream downloads
and are **not** committed — see [Reproducing the build](#reproducing-the-build).

> **Parameter values live in [`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md).**
> That file is the authority. `config/master.cfg` is the *upstream wfb-ng template*, not the
> deployed configuration, and the two deployment guides were written against it — so both
> disagree with the running system on channel, ports, key paths and addresses.

---

## What this device actually does

The CPE610 is **not** a standalone receiver. It is a cluster node: the relay
(`vind-rly`, 10.5.7.100) runs `wfb-server --profiles gs --cluster ssh` and drives two RF
nodes over SSH — its own RTL8812EU card, and this CPE610's `phy0-mon0` at 10.5.7.102.

```
        Drone (WFB-NG TX)
               │  5 GHz raw Wi-Fi, ch161 / 5805 MHz / HT20
       ┌───────┴────────┐
       ▼                ▼
  CPE610 v2        RTL8812EU
  phy0-mon0        wlx00c0cab6db3b
  (ath9k, RX)      (relay's own card)
  10.5.7.102            │
       │  Ethernet      │
       └───────┬────────┘
               ▼
      Relay  10.5.7.100  ── wfb-server --cluster ssh
               │
               ▼  10.5.6.0/24
      Laptop / GS  10.5.6.50
```

Two consequences that surprise people, both expected and neither a fault:

- **The node has no internet, by design.** It has one radio; it cannot be a station and a
  channel-161 monitor at the same time, so `radio0` is disabled and there is no default
  route and no package feed. Anything you want installed must be carried in as an `.ipk`
  over Ethernet.
- **It is effectively RX-only whatever you configure.** ath9k reports true dBm and no noise
  figure (so SNR reads 0), while the relay's RTL8812EU reports `rssi_avg` +14..+16. Against
  `tx_sel_rssi_delta = 3` the relay card always wins TX arbitration. Its RX contribution is
  real and measured: 220 packets vs the local card's 233 in the same window, `dec_err: [0, 0]`.

---

## Hardware / build matrix

| Item | Value |
| --- | --- |
| Board | TP-Link CPE610 v2 (Atheros AR9344, 8 MB flash / 64 MB RAM) |
| OpenWrt release | 24.10.4 (`r28959-29397011cc`) |
| Target / subtarget | `ath79` / `generic` |
| Package arch | `mips_24kc` |
| Toolchain | `gcc-13.3.0`, musl |
| Kernel | 6.6.110 (`35ef4dd36891d37023436baa842fa311`) |
| Radio | ath9k (`kmod-ath9k`) |
| wfb-ng **in the image and on the device** | **25.01-r1** |
| wfb-ng **in this repo's recipes / `.ipk`s** | 24.9.7-r2 — stale, see below |

### ⚠ The committed recipes cannot rebuild the committed image

`package/wfb-ng/Makefile` and `package/wfb-ng-full/Makefile` pin `PKG_VERSION:=24.9.7`
(`svpcom/wfb-ng@3a05304`), and `packages/ipk/*.ipk` are the 24.9.7-r2 artifacts. Both are
leftovers from an earlier build. The image in `images/custom/` and the running device are
**25.01-r1**, built from upstream `wfb-ng/openwrt/net/{wfb-ng,wfb-ng-full}` at a newer
commit that is not in this repo.

So: the images here are the real deployed firmware, but rebuilding from the recipes here
will *not* reproduce them. Closing this gap means re-importing the 25.01 recipes (or newer
— relay and drone already run 25.4.27.73439) and rebuilding.

---

## Layout

```
package/                      Custom OpenWrt package recipes
  wfb-ng/                       base build: wfb_rx / wfb_tx binaries + wfb-ng-tun
  wfb-ng-full/                  full build: adds Python stack, wfb-server, wfb_keygen
config/
  sdk.config                    SDK .config used to build the .ipk packages
  sdk-feeds.conf.default        feed revisions the SDK was pinned to
  imagebuilder.config           ImageBuilder .config used to build the images
  imagebuilder-repositories.conf  ImageBuilder package repositories
  master.cfg                    UPSTREAM wfb-ng template — NOT the deployed config
images/
  custom/                       PXLABS images (wfb-ng baked in) + manifest, SBOM, sha256sums
  stock/                        Unmodified OpenWrt 24.10.4 release images, for recovery
packages/ipk/                   Built wfb-ng .ipk packages (mips_24kc) — 24.9.7-r2, stale
stock-firmware/                 TP-Link factory config backup taken off the unit
deployment/                     Snapshot of the RUNNING node, captured 2026-09-26 (evidence)
docs/
  DEPLOYED_PARAMETERS.md        ← authoritative parameter reference; read this first
  *_Deployment_Guide.md         Narrative build/deploy procedure, corrections applied inline
  *_Deployment_Guide*.docx      The original Word documents, kept as-is
```

### `package/wfb-ng` vs `package/wfb-ng-full`

Two distinct recipes, not duplicates:

- **`wfb-ng`** — binaries only (`wfb_rx`, `wfb_tx`, `wfb_tun`). Deps: `libpcap libsodium
  libstdcpp`. Builds `wfb-ng` + `wfb-ng-tun`. **This is what the node runs** — no
  `wfb-server` on the CPE610.
- **`wfb-ng-full`** — adds the Python control plane (`python3-twisted`, `pyserial`,
  `msgpack`, `jinja2`, `pyroute2`, `bash`, `iw`, `openssh-client`), ships `wfb-server` as a
  cluster *manager*, plus `wfb_tx_cmd` / `wfb_keygen`, and reads `/etc/wifibroadcast.cfg`.
  `CONFLICTS:=wfb-ng`. Heavier — watch the CPE610 flash budget.

The ImageBuilder's copy of the `wfb-ng` recipe (`package/network/utils/wfb-ng/`) is
byte-identical to the SDK's, so it is committed once here. Copy it into both trees.

---

## Why the firmware must be custom

`/overlay` on this device has **~450 KB free** and `libstdcpp6` alone needs ~2 MB:

```
verify_pkg_installable: Only have 480kb available on filesystem /overlay
pkg libstdcpp6 needs 2070
```

Removing packages does not help, squashfs `/overlay` cannot be resized, and external
storage is not reliable here. `opkg install wfb-ng` can never work on a CPE610 — WFB-NG has
to be baked in with ImageBuilder. That is the whole reason this repo exists.

---

## Images

`images/custom/` is built by the ImageBuilder from `config/imagebuilder.config`, with the
wfb-ng `.ipk`s injected via `packages-local/`.

| File | Size | MD5 |
| --- | --- | --- |
| `custom/…-squashfs-factory.bin` | 6,964,588 | `baf447c623541396a9c1329a68998974` |
| `custom/…-squashfs-sysupgrade.bin` | 7,804,077 | `2d83bb2a755b3be6571ea1395ad35f8d` |
| `stock/…-squashfs-factory.bin` | 6,571,372 | `8f833c9ed9eccf7c2682ad2617447e53` |
| `stock/…-squashfs-sysupgrade.bin` | 7,803,579 | `248d93c93ae6027d2805f35e493fae9b` |

SHA256 for the custom pair is in `images/custom/sha256sums`, the package list in
`images/custom/…manifest`, the SBOM in `…bom.cdx.json`.

**The committed custom image is the deployed firmware, near-exactly.** Its manifest and
`deployment/packages-installed.txt` share **118 packages at identical versions**; the device
adds only `ethtool` and `tcpdump`, baked into a slightly later build. Do not describe the
image as "close to" deployment — it matches.

**Flashing**

- From stock TP-Link Pharos firmware → **factory** image via the web UI.
- From an existing OpenWrt install → **sysupgrade** image (`sysupgrade -n <image>`; `-n`
  drops old config, which you want when the wfb-ng layout changed).

`stock-firmware/CPE610-v2_stock_config.bin` is the config backup pulled off the unit
*before* conversion — keep it, it is the only route back to the vendor configuration.

---

## Reproducing the build

Nothing here is a ready-to-build tree; the two upstream toolchains must be re-fetched. Note
the version caveat above before trusting the output.

### 1. wfb-ng `.ipk` packages (OpenWrt SDK)

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

Output lands in `bin/packages/mips_24kc/base/`.

The recipe fetches wfb-ng from `https://github.com/svpcom/wfb-ng.git` at `3a05304`, so a
local clone is not required. The clone at `~/owrt/wfb-ng` is pristine `master` at `109e1ad`
(2025-12-20) — **97 commits ahead of the pin**, zero local changes, never built.

### 2. Firmware images (OpenWrt ImageBuilder)

```bash
cd ~/owrt
wget https://downloads.openwrt.org/releases/24.10.4/targets/ath79/generic/openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
tar --zstd -xf openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64.tar.zst
cd openwrt-imagebuilder-24.10.4-ath79-generic.Linux-x86_64

cp /path/to/PXLABS_OpenWrt_CPE610/config/imagebuilder.config .config
cp /path/to/PXLABS_OpenWrt_CPE610/config/imagebuilder-repositories.conf repositories.conf
mkdir -p packages-local
cp /path/to/PXLABS_OpenWrt_CPE610/packages/ipk/*.ipk packages-local/
mkdir -p package/network/utils
cp -r /path/to/PXLABS_OpenWrt_CPE610/package/wfb-ng package/network/utils/

make image PROFILE=tplink_cpe610-v2 \
     PACKAGES="wfb-ng wfb-ng-tun kmod-tun libsodium libpcap" \
     FILES=files/
```

Output lands in `bin/targets/ath79/generic/`. Image hashes are **not** bit-reproducible
across ImageBuilder extractions because `key-build` (the package-signing key) is regenerated
each time; that key is gitignored deliberately.

---

## Runtime configuration

The node has no `wifibroadcast.cfg` of its own. It runs the base `wfb-ng` + `wfb-ng-tun`
pair and is driven entirely over cluster-ssh from the relay, so the relay's
`/etc/wifibroadcast.cfg` is the only place the link parameters exist. A copy is preserved at
[`deployment/wifibroadcast.cfg.relay`](deployment/wifibroadcast.cfg.relay) and the values
are documented in [`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md).

`config/master.cfg` is the **upstream template** and is kept only for reference and diffing.
Do not deploy from it.

One behaviour worth knowing up front: `phy0-mon0` is created by the relay on every cluster
start via `custom_init_script`, **not** at boot — `deployment/etc/rc.local` is stock and
there is no `/etc/init.d/wfb-mon0`, contrary to what the guides instruct. Reboot the node on
its own and it has no monitor interface until the relay's cluster service restarts.

---

## Security

No crypto material is stored in this repo, and none should be. `*.key` is gitignored, and
the house SSID PSK in `deployment/etc/config/wireless` is redacted. Generate wfb-ng keypairs
with `wfb_keygen` (from `wfb-ng-full`) and distribute them out of band.

🔴 **Open item, tracked outside this repo:** the public `ArvinVeiyon/Relay_Station_Pxlabs`
repo — the upstream source of the `deployment/` snapshot — still has real `gs.key`,
`drone.key` and `wfb_cluster_ed25519` on its default branch, fetchable unauthenticated.
Remediation needs key **rotation** plus a history purge, not a delete commit. Details in
[`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md#security).

---

## Not in this repo, and why

| Excluded | Size | Reason |
| --- | --- | --- |
| `openwrt-sdk-24.10.4-…/` | 3.5 GB | Upstream; re-fetch per above |
| `openwrt-imagebuilder-24.10.4-…/` | 1.2 GB | Upstream; re-fetch per above |
| `sdk.tar.zst` | 199 MB | Over GitHub's 100 MB per-file limit |
| `ib.tar.zst` | 103 MB | Over GitHub's 100 MB per-file limit |
| `~/owrt/wfb-ng/` | 6 MB | Pristine clone of `svpcom/wfb-ng`, zero local changes; pinned by commit in the recipe |
| `dl/` tarballs | 425 MB | Upstream source archives, re-downloaded by the build |
| `key-build*`, `keys/` | — | Regenerated per extraction; signing keys don't belong in git |
