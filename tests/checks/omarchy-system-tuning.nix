# omarchy.systemTuning.enable contract (docs/options.md): the demo
# default carries every tuning entry; `false` removes all of them
# (including the normal-priority modprobe/udev lines that otherwise
# need mkForce); `zramSwap.enable = false` removes only the zram
# reclaim sysctls and the zswap switch.
{
  self,
  pkgs,
  ...
}:
let
  demo = self.nixosConfigurations.demo;
  ext = m: (demo.extendModules { modules = [ m ]; }).config;
  zramSysctls = [
    "vm.swappiness"
    "vm.vfs_cache_pressure"
    "vm.page-cluster"
    "vm.watermark_boost_factor"
    "vm.watermark_scale_factor"
  ];
  otherSysctls = [
    "net.ipv4.tcp_congestion_control"
    "net.core.default_qdisc"
    "net.ipv4.tcp_mtu_probing"
    "vm.dirty_background_bytes"
    "vm.dirty_bytes"
    "vm.dirty_writeback_centisecs"
  ];
  probe = c: {
    zram = builtins.filter (k: c.boot.kernel.sysctl ? ${k}) zramSysctls;
    other = builtins.filter (k: c.boot.kernel.sysctl ? ${k}) otherSysctls;
    usb = builtins.match ".*usbcore autosuspend=-1.*" c.boot.extraModprobeConfig != null;
    kyber = builtins.match ".*kyber.*" c.services.udev.extraRules != null;
    zswap = builtins.any (
      r: builtins.match ".*/sys/module/zswap/.*" r != null
    ) c.systemd.tmpfiles.rules;
  };
  expect =
    name: got: want:
    if got == want then
      true
    else
      throw "omarchy-system-tuning: ${name}: got ${builtins.toJSON got}, want ${builtins.toJSON want}";
  all = {
    zram = zramSysctls;
    other = otherSysctls;
    usb = true;
    kyber = true;
    zswap = true;
  };
in
assert expect "demo default" (probe demo.config) all;
assert expect "systemTuning.enable = false"
  (probe (ext {
    omarchy.systemTuning.enable = false;
  }))
  {
    zram = [ ];
    other = [ ];
    usb = false;
    kyber = false;
    zswap = false;
  };
assert expect "zramSwap.enable = false"
  (probe (ext {
    zramSwap.enable = false;
  }))
  (
    all
    // {
      zram = [ ];
      zswap = false;
    }
  );
pkgs.runCommand "omarchy-system-tuning" { } "touch $out"
