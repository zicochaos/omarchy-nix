# Testing omarchy-nix in a VM

We test omarchy-nix inside a NixOS VM built from a config that consumes the
flake, not by booting the upstream minimal ISO. The ISO + OVMF + q35
combination is flaky on AMD Strix Halo hosts (early OVMF init trips a KVM
emulation failure / black screen), and it would force a manual install step
that the declarative flake path makes redundant.

## Canonical path: build the `example` flake output

`example/configuration.nix` consumes the omarchy-nix NixOS module exactly the
way an external consumer does and is wired in-repo as
`nixosConfigurations.example` (evaluated by `nix flake check`). To build and
run it as a VM:

```bash
cd ~/Projects/omarchy-nix

# Build the VM (first build is slow; subsequent builds reuse the cache).
nix build .#nixosConfigurations.example.config.system.build.vm

# Run headless on the serial console (Ctrl-A X to exit QEMU).
QEMU_OPTS="-nographic" QEMU_KERNEL_PARAMS="console=ttyS0" ./result/bin/run-nixos-vm

# Or with a GUI window (needed for Hyprland + quickshell).
QEMU_OPTS="-device virtio-gpu-pci" ./result/bin/run-nixos-vm
```

The wrapper script handles QEMU flags, KVM, the disk image, the shared `/tmp`
via 9p, and EFI setup. Do not roll a custom QEMU command line unless the
wrapper demonstrably can't do what a test needs; it almost always can.

## State and reset

The VM's state lives in `nixos.qcow2` next to `result/`. Delete it to reset
the VM to first boot:

```bash
rm -f nixos.qcow2
```

## Automated desktop test

The canonical verification is an automated NixOS test that runs under
`nix flake check`:

```
checks.x86_64-linux.omarchy-desktop
```

`nix flake check` runs it automatically. It boots a VM with
`-device virtio-gpu-pci`, logs in via tty1 autologin (more robust to drive
headlessly than SDDM), and asserts the whole stack came up:

1. The Wayland socket appears (`/run/user/1000/wayland-1`), proof the
   Hyprland Lua config chain (bootstrap → `require default.hypr.omarchy` →
   user stubs) loaded without error and the compositor initialized.
2. `quickshell list` returns a registered instance, proof `shell.qml`
   loaded successfully against nixpkgs's quickshell (API mismatch would
   leave the list empty).
3. A screenshot is captured for diagnostics.

Run just the test:

```bash
nix build .#checks.x86_64-linux.omarchy-desktop
nix log .#checks.x86_64-linux.omarchy-desktop   # full VM log
```

### Known QEMU limitation

Hyprland uses Aquamarine (not wlroots), which requires GL. QEMU without
virgil gives no GLES2, so `WLR_RENDERER=pixman` (the sway test's fallback)
does not help here; the framebuffer screenshot may be near-empty. This
is a QEMU rendering limitation, not a desktop failure. The
process-level assertions (Wayland socket, quickshell instance) are the
source of truth; the screenshot is supplementary. On real hardware the
desktop renders normally.

## Manual desktop exploration (debugging)

For interactive debugging, build the demo VM and run it with a GPU device:

```bash
nix build .#nixosConfigurations.demo.config.system.build.vm --out-link result-vm
QEMU_OPTS="-device virtio-vga" ./result-vm/bin/run-nixos-vm
```

This opens a QEMU window on the host's display. Log in as `demo` / `demo`
at SDDM and the desktop should come up.

If quickshell fails to load (API mismatch with nixpkgs's pinned version),
add the `quickshell` flake input documented in `flake.nix` and switch to
its `#quickshell` package, then rebuild.

## Why not the minimal ISO

We tried it. The combination of `q35` + OVMF + the NixOS minimal ISO on this AMD
host (Strix Halo laptop) gives a black screen: OVMF init either triple-faults
(`KVM internal error. Suberror: 1` at real-mode `EIP≈0x6a50`, in option-ROM
territory) or silently hangs with no serial output. `-cpu host` vs `-cpu EPYC`
makes no difference; only dropping OVMF and the ISO resolves it. Since the
declarative `nix-build -A vm` path is also the better fit for testing a flake,
the ISO path is not worth pursuing. If a future stage genuinely needs the ISO
(e.g. testing the real Omarchy installer), revisit on a different host.

## QEMU/KVM availability

The VM needs `/dev/kvm` on the host; `qemu_kvm` is available via
`nix build nixpkgs#qemu_kvm`. No system-level install (libvirtd,
virt-manager) is required; the `run-nixos-vm` wrapper is self-contained.
