# AnyMeta

AnyMeta is a KernelSU metamodule that makes mounting backends switchable. It keeps the active backend, downloaded packages, and backups in `/data/adb/AnyMeta`; regular modules remain in place, so changing OverlayFS/Magic Mount implementations does not erase module data.

## What it does

- Switches the six backends published by the KernelSU Modules Repo while keeping one KernelSU metamodule installed.
- Resolves `depends=` in topological order, rejects dependency cycles, installs embedded dependency ZIPs, and can fetch missing packages from a local `registry.json`.
- Installs local ZIPs or builds directly from a Git repository with the bundled Android `kam` binary.
- Uses a global cache and configurable proxy fallback (`ANYMETA_PROXY_BASE`) for GitHub downloads.
- Shows an update prompt when the active backend has a newer stable release; failed updates leave the previous runtime intact.
- Creates portable backups of backend state and cache metadata.
- Ships a KernelSU WebUI with backend cards, switching, update prompts, backup, and diagnostics. When another active metamodule is present, its own WebUI is shown.
- Publishes a separate `anymeta-installer.zip` that downloads and verifies the latest AnyMeta release before handing it to KernelSU.

## Install

Build with [Kam](https://github.com/MemDeco-WG/Kam):

```sh
kam validate
kam check
kam build
```

Install `dist/AnyMeta.zip` directly when no other metamodule is active. If a metamodule is already installed, install `dist/anymeta-installer.zip`; the installer backs it up, stages AnyMeta, and completes the takeover on reboot. Open the AnyMeta WebUI from the module action button.

## Device commands

The same controller is available over ADB/root:

```sh
/data/adb/modules/AnyMeta/anymeta.sh list
/data/adb/modules/AnyMeta/anymeta.sh use meta-overlayfs
/data/adb/modules/AnyMeta/anymeta.sh install /sdcard/Download/module.zip
/data/adb/modules/AnyMeta/anymeta.sh repo-install MODULE_ID
/data/adb/modules/AnyMeta/anymeta.sh git-build https://github.com/user/module
/data/adb/modules/AnyMeta/anymeta.sh backup
/data/adb/modules/AnyMeta/anymeta.sh doctor
```

For dependency fetching, place a JSON map such as `{"foo":{"url":"https://.../foo.zip"}}` at `/data/adb/AnyMeta/registry.json`, or package dependencies under `dependencies/<id>.zip` inside the main module archive.

`use` changes only the selected backend. It never deletes `/data/adb/modules/*`. A backend must expose the standard KernelSU `metamount.sh`; its optional `metainstall.sh` and `metauninstall.sh` hooks are delegated too.

## Backend source

`src/AnyMeta/backends.json` is the curated index. The weekly `Update backend index` workflow pulls the upstream KernelSU Next Modules Repo list and opens a normal repository update commit. Release builds run Kam validation, shell checks, ZIP verification, and GitHub artifact publishing.

The official KernelSU organization submission and mirror workflow are documented in [docs/ksu-publishing.md](docs/ksu-publishing.md).

## Safety model

Only AnyMeta is installed as `metamodule=1`, satisfying KernelSU's single-active-metamodule rule. Backend archives are unpacked under `/data/adb/AnyMeta/backends/<id>`. A checksum listed in the index is mandatory for that entry; unverifiable or failed downloads are never activated.

## License

AnyMeta is MIT. The bundled bootstrap backend remains GPL-3.0; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
