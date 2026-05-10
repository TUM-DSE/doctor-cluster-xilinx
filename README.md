# doctor-cluster-xilinx

Doctor-cluster Xilinx environment metadata for FPGA development workflows.

This flake describes site-specific infrastructure needed by Xilinx FPGA projects on the Doctor cluster. It is a configuration/data layer: it does not build project artifacts and does not provide generic Coyote tooling.

## Scope

This repository provides:

- the Doctor Xilinx installation root,
- the Doctor `xilinx-shell` package,
- host kernels from `doctor-cluster-config` for out-of-tree driver builds,
- FPGA inventory metadata for Doctor hosts,
- board-level Doctor Xilinx version policy,
- Doctor-supported Coyote target platforms,
- Doctor Xilinx license-file environment conventions.

This repository does not provide:

- Coyote build functions,
- Vivado/Vitis wrapper implementations,
- project-specific hardware or software packages,
- project-specific bitstream names,
- project-specific synthesis/routing/bitgen graphs.

Those concerns belong in the consuming project and/or in a generic tooling flake.

## Intended composition model

A project flake is expected to compose three kinds of inputs:

1. generic tooling, such as `coyote-nix`,
2. site metadata, such as this flake,
3. project-specific source layout and build graph.

This keeps site policy separate from both generic tooling and project-specific builds. Another deployment site can provide a flake with the same shape and be substituted by the project flake.

## Flake interface

Main entry point:

```nix
doctor-cluster-xilinx.lib.mkXilinxContext {
  inherit pkgs system;
}
```

The returned context contains:

```nix
{
  xilinxShareRoot = "/share/xilinx";
  xilinxShell = ...;
  targetPlatforms = [ "ultrascale_plus" "versal" ];
  driverKernels = { ... };
  packages = { ... };
  nixosConfigurations = { ... };

  boards = { ... };
  hosts = { ... };
  getHost = hostName: ...;
  getFpga = hostName: fpgaName: ...;
  getDefaultFpga = hostName: ...;
  hostFpgaEnvShellFragment = ''...'';

  licenseFileFor = hostName: ...;
  licenseEnvFor = hostName: ...;
}
```

Lower-level helpers are also exported:

```nix
doctor-cluster-xilinx.lib.xilinxShareRoot
doctor-cluster-xilinx.lib.targetPlatforms
doctor-cluster-xilinx.lib.boards
doctor-cluster-xilinx.lib.hosts
doctor-cluster-xilinx.lib.mkXilinxShell
doctor-cluster-xilinx.lib.mkDriverKernels
doctor-cluster-xilinx.lib.licenseFileFor
doctor-cluster-xilinx.lib.licenseEnvFor
doctor-cluster-xilinx.lib.getHost
doctor-cluster-xilinx.lib.getFpga
doctor-cluster-xilinx.lib.getDefaultFpga
doctor-cluster-xilinx.lib.hostFpgaEnvShellFragment
```

## Example use from a project flake

```nix
let
  doctor = doctor-cluster-xilinx.lib.mkXilinxContext {
    inherit pkgs system;
  };

  tools = coyote-nix.lib.mkTools {
    inherit pkgs coyoteRoot;
    inherit (doctor) xilinxShareRoot;
  };
in
coyote-nix.lib.mkCoyoteBoardPackages {
  inherit pkgs tools coyoteRoot;
  inherit (doctor) xilinxShareRoot xilinxShell;
  hwSource = ./hw;
  pnamePrefix = "my-project";
  projectName = "my-project";
  boards = {
    u280 = {
      inherit (doctor.boards.u280) xilinxVersion simXilinxVersion;
    };
    v80 = {
      inherit (doctor.boards.v80) xilinxVersion simXilinxVersion;
    };
  };
}
```

## Board and target-platform policy

Currently encoded Coyote target platforms:

- `ultrascale_plus`
- `versal`

Currently encoded board-level Xilinx policy:

- `u280.xilinxVersion = "2023.2"`
- `u280.simXilinxVersion = "2022.2"`
- `v80.xilinxVersion = "2025.1"`
- `v80.simXilinxVersion = "2025.1"`

## Host facts

`hostFpgaEnvShellFragment` is a shell fragment for dev shells. At shell-entry time it detects the short hostname and current `FDEV_NAME`, then exports Doctor host-specific deployment facts such as `FPGA_BDF`, `FPGA_PART_HINT`, and `TARGET_PLATFORM` when an entry is known. Set `DOCTOR_CLUSTER_XILINX_HOST` to override hostname detection.

Currently encoded FPGA entries:

- `amy.u280`
- `clara.u280`
- `rose.u280`
- `rose.v80`
