# AnyMeta Installer

KernelSU installer for the latest AnyMeta release. It verifies GitHub's SHA-256
asset digest, backs up and adopts an existing metamodule, stages AnyMeta, and
switches `/data/adb/metamodule` for the next boot.

The installer is required when another metamodule is active because KernelSU
rejects a second metamodule before the target `customize.sh` can run. It supports
Android arm64 and must be installed from a booted KernelSU Manager.
