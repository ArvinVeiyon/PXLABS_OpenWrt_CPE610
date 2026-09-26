# PXLABS_OpenWrt_CPE610

Custom OpenWrt 24.10.4 firmware for the **TP-Link CPE610 v2** (target `ath79/generic`,
arch `mips_24kc`), carrying **wfb-ng 24.9.7-r2** so the unit acts as a long-range
WFB-NG ground-station receiver.

This repo holds the *sources, build configuration and flashable artifacts only*. The
OpenWrt SDK (3.5 GB) and ImageBuilder (1.2 GB) are upstream downloads and are **not**
committed — see [Reproducing the build](#reproducing-the-build).

---

## Hardware / build matrix

| Item | Value |
| --- | --- |
| Board | TP-Link CPE610 v2 |
| OpenWrt release | 24.10.4 |
| Target / subtarget | `ath79` / `generic` |
| Package arch | `mips_24kc` |
| Toolchain | `gcc-13.3.0`, musl |
| Kernel | 6.6.110 (`35ef4dd36891d37023436baa842fa311`) |
| Radio | ath9k (`kmod-ath9k`) |
| wfb-ng version | 24.9.7-r2 |
| wfb-ng source commit | `3a053040442174e6c1ce76866c6da4b12c19dbb4` (2024-10-09, `wfb-ng-24.09.23-13-g3a05304`) |

---

## Layout

```
package/                      Custom OpenWrt package recipes (the actual PXLABS work)
  wfb-ng/                       base build: wfb_rx / wfb_tx binaries + wfb-ng-tun
  wfb-ng-full/                  full build: adds Python stack, wfb-server, wfb_keygen
config/
  sdk.config                    SDK .config used to build the .ipk packages
  sdk-feeds.conf.default        feed revisions the SDK was pinned to
  imagebuilder.config           ImageBuilder .config used to build the images
  imagebuilder-repositories.conf  ImageBuilder package repositories
  master.cfg                    wfb-ng runtime config (ch165 / 5825 MHz, region BO)
images/
  custom/                       PXLABS images (wfb-ng baked in) + manifest, SBOM, sha256sums
  stock/                        Unmodified OpenWrt 24.10.4 release images, for reference/recovery
packages/ipk/                   Built wfb-ng .ipk packages (mips_24kc)
stock-firmware/                 TP-Link factory config backup taken off the unit
docs/                           Deployment guides (.docx)
```

### `package/wfb-ng` vs `package/wfb-ng-full`

Two distinct recipes, not duplicates:

- **`wfb-ng`** — binaries only (`wfb_rx`, `wfb_tx`, `wfb_tun`). Deps: `libpcap libsodium
  libstdcpp`. Builds `wfb-ng` + `wfb-ng-tun`. Acts as a cluster *node*, standalone
  receiver or transmitter, no diversity. This is what the committed `.ipk`s are.
- **`wfb-ng-full`** — adds the Python control plane (`python3-twisted`, `pyserial`,
  `msgpack`, `jinja2`, `pyroute2`, `bash`, `iw`, `openssh-client`), ships `wfb-server`
  as a cluster *manager*, plus `wfb_tx_cmd` / `wfb_keygen`, and reads
  `/etc/wifibroadcast.cfg`. `CONFLICTS:=wfb-ng`. Heavier — watch CPE610 flash budget.

The ImageBuilder's copy of the `wfb-ng` recipe (`package/network/utils/wfb-ng/`) is
byte-identical to the SDK's, so it is committed once here. Copy it into both trees.

---

## Images

`images/custom/` is built by the ImageBuilder from `config/imagebuilder.config`, with the
locally-built wfb-ng `.ipk`s injected via `packages-local/`.

| File | Size | MD5 |
| --- | --- | --- |
| `custom/…-squashfs-factory.bin` | 6,964,588 | `baf447c623541396a9c1329a68998974` |
| `custom/…-squashfs-sysupgrade.bin` | 7,804,077 | `2d83bb2a755b3be6571ea1395ad35f8d` |
| `stock/…-squashfs-factory.bin` | 6,571,372 | `8f833c9ed9eccf7c2682ad2617447e53` |
| `stock/…-squashfs-sysupgrade.bin` | 7,803,579 | `248d93c93ae6027d2805f35e493fae9b` |

SHA256 for the custom pair is in `images/custom/sha256sums`; the exact package list is in
`images/custom/…manifest` and the SBOM in `…bom.cdx.json`.

**Flashing**

- From stock TP-Link Pharos firmware → use the **factory** image via the web UI.
- From an existing OpenWrt install → use the **sysupgrade** image
  (`sysupgrade -n <image>`; `-n` drops old config, which you want when the wfb-ng
  layout changed).

`stock-firmware/CPE610-v2_stock_config.bin` is the config backup pulled off the unit
*before* conversion — keep it, it is the only route back to the vendor configuration.

---

## Reproducing the build

Nothing here is a ready-to-build tree; the two upstream toolchains must be re-fetched.

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

The recipe fetches wfb-ng from `https://github.com/svpcom/wfb-ng.git` at commit
`3a05304`, so a local clone is not required. Note the clone at `~/owrt/wfb-ng` is on
`master` at `109e1ad` (2025-12-20) — **97 commits ahead of the pin** and never built.
Bumping `PKG_SOURCE_VERSION` to it is untested.

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

Output lands in `bin/targets/ath79/generic/`. Compare against
`images/custom/sha256sums` — note image hashes are not bit-reproducible across
ImageBuilder extractions because `key-build` (the package-signing key) is regenerated
each time; that key is gitignored deliberately.

---

## Runtime configuration

`config/master.cfg` is the wfb-ng config (upstream `master.cfg`) as used for this
deployment. Notable settings:

- `wifi_channel = 165` → 5825 MHz, 20 MHz width
- `wifi_region = 'BO'` (permissive CRDA region)
- `radio_mtu = 1445`, `mavlink_agg_timeout = 0.1`, `tunnel_agg_timeout = 0.005`
- `wifi_txpower = None` → driver default

It references keypairs `gs.key` / `drone.key` / `bind.key` **by filename only** — no
crypto material is stored in this repo, and none should be. Generate with `wfb_keygen`
(from `wfb-ng-full`) and distribute out of band. `*.key` is gitignored.

Deployment procedure is in `docs/CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide*.docx`
(`_v1` is a separate revision, not a duplicate).

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
