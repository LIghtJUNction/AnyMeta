# AnyMeta

AnyMeta is a KernelSU metamodule that makes mounting backends switchable. It keeps the active backend, downloaded packages, and backups in `/data/adb/AnyMeta`; regular modules remain in place, so changing OverlayFS/Magic Mount implementations does not erase module data.

## What it does

- Switches the six backends published by the KernelSU Next Modules Repo while keeping one KernelSU metamodule installed.
- Resolves `depends=` from module packages before installation, rejects dependency cycles, and records the install order.
- Installs local ZIPs, cached/remote KSU packages, or builds directly from a Git repository with `kam build`.
- Uses a global cache and configurable proxy fallback (`ANYMETA_PROXY_BASE`) for GitHub downloads.
- Creates portable backups of backend state and cache metadata.
- Ships a KernelSU WebUI with backend cards, cache state, switching, download, backup, and diagnostics.

## Install

Build with [Kam](https://github.com/MemDeco-WG/Kam):

```sh
kam validate
kam check
kam build
```

Install `dist/AnyMeta.zip` from KernelSU Manager and reboot. Open the AnyMeta WebUI from the module action button.

## Device commands

The same controller is available over ADB/root:

```sh
/data/adb/modules/AnyMeta/anymeta.sh list
/data/adb/modules/AnyMeta/anymeta.sh use meta-overlayfs
/data/adb/modules/AnyMeta/anymeta.sh install /sdcard/Download/module.zip
/data/adb/modules/AnyMeta/anymeta.sh git-build https://github.com/user/module
/data/adb/modules/AnyMeta/anymeta.sh backup
/data/adb/modules/AnyMeta/anymeta.sh doctor
```

`use` changes only the selected backend. It never deletes `/data/adb/modules/*`. A backend must expose the standard KernelSU `metamount.sh`; its optional `metainstall.sh` and `metauninstall.sh` hooks are delegated too.

## Backend source

`src/AnyMeta/backends.json` is the curated index. The weekly `Update backend index` workflow pulls the upstream KernelSU Next Modules Repo list and opens a normal repository update commit. Release builds run Kam validation, shell checks, ZIP verification, and GitHub artifact publishing.

The official KernelSU organization submission and mirror workflow are documented in [docs/ksu-publishing.md](docs/ksu-publishing.md).

## Safety model

Only AnyMeta is installed as `metamodule=1`, satisfying KernelSU's single-active-metamodule rule. Backend archives are unpacked under `/data/adb/AnyMeta/backends/<id>`. A checksum listed in the index is mandatory for that entry; unverifiable or failed downloads are never activated.

## License

MIT
