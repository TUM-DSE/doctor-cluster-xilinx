{ doctor-cluster-config }:

let
  lib = doctor-cluster-config.inputs.nixpkgs.lib;

  xilinxShareRoot = "/share/xilinx";

  normalizeMac = mac: lib.toUpper (builtins.replaceStrings [ ":" ] [ "" ] mac);

  targetPlatforms = [
    "ultrascale_plus"
    "versal"
  ];

  boards = {
    u280 = {
      board = "u280";
      family = "ultrascale";
      coyotePlatform = "ultrascale";
      targetPlatform = "ultrascale_plus";
      partHint = "xcu280";
      xilinxVersion = "2023.2";
      simXilinxVersion = "2022.2";
    };

    v80 = {
      board = "v80";
      family = "versal";
      coyotePlatform = "versal";
      targetPlatform = "versal";
      partHint = "xcv80";
      xilinxVersion = "2025.1";
      simXilinxVersion = "2025.1";
    };
  };

  mkU280 =
    {
      bdf,
      mac,
      ipAddr,
      ipAddrHex,
      jtagTarget ? null,
      hwServerPort ? null,
    }:
    boards.u280
    // {
      inherit bdf;
      coyoteNetwork = {
        inherit ipAddr ipAddrHex mac;
        macAddr = normalizeMac mac;
        driverArgs = "ip_addr=${ipAddrHex} mac_addr=${normalizeMac mac}";
      };
    }
    // lib.optionalAttrs (jtagTarget != null) { inherit jtagTarget; }
    // lib.optionalAttrs (hwServerPort != null) { inherit hwServerPort; };

  mkV80 =
    {
      bdf,
      jtagTarget ? null,
      hwServerPort ? null,
    }:
    boards.v80
    // {
      inherit bdf;
    }
    // lib.optionalAttrs (jtagTarget != null) { inherit jtagTarget; }
    // lib.optionalAttrs (hwServerPort != null) { inherit hwServerPort; };

  hosts = {
    amy = {
      defaultFpga = "u280";
      fpgas.u280 = mkU280 {
        bdf = "0000:e1:00.0";
        ipAddr = "10.0.0.1";
        ipAddrHex = "0x0A000001";
        mac = "00:0A:35:0E:24:D6";
      };
    };

    clara = {
      defaultFpga = "u280";
      fpgas.u280 = mkU280 {
        bdf = "0000:e1:00.0";
        ipAddr = "10.0.0.2";
        ipAddrHex = "0x0A000002";
        mac = "00:0A:35:0E:24:F2";
      };
    };

    rose = {
      defaultFpga = "u280";
      fpgas = {
        u280 = mkU280 {
          bdf = "0000:c1:00.0";
          ipAddr = "10.0.0.3";
          ipAddrHex = "0x0A000003";
          mac = "00:0A:35:0E:24:E6";
          jtagTarget = "217702174005A";
          hwServerPort = "3121";
        };
        v80 = mkV80 {
          bdf = "0000:61:00.0";
          jtagTarget = "XFL1EZVSAG4SA";
          hwServerPort = "3122";
        };
      };
    };
  };

  mkXilinxShell =
    {
      pkgs,
      system ? pkgs.stdenv.hostPlatform.system,
      xilinxName ? "xilinx-shell",
      runScript ? "bash",
    }:
    let
      doctorPackages = doctor-cluster-config.packages.${system} or { };
    in
    if !(pkgs.stdenv.hostPlatform.isx86_64 && pkgs.stdenv.hostPlatform.isLinux) then
      throw "doctor-cluster-xilinx: Xilinx shell is only available on x86_64-linux"
    else if !(doctorPackages ? xilinx-env) then
      throw "doctor-cluster-xilinx: doctor-cluster-config does not provide packages.${system}.xilinx-env"
    else
      doctorPackages.xilinx-env.override {
        inherit xilinxName runScript;
      };

  mkDriverKernels =
    {
      pkgs,
      system ? pkgs.stdenv.hostPlatform.system,
    }:
    if !(pkgs.stdenv.hostPlatform.isx86_64 && pkgs.stdenv.hostPlatform.isLinux) then
      { }
    else
      lib.mapAttrs (_hostName: hostCfg: hostCfg.config.boot.kernelPackages.kernel) (
        lib.filterAttrs (
          hostName: hostCfg:
          hostCfg.pkgs.stdenv.hostPlatform.system == system && !(lib.hasPrefix "install-iso-" hostName)
        ) doctor-cluster-config.nixosConfigurations
      );

  licenseFileFor = hostName: "${xilinxShareRoot}/licenses/Xilinx_${hostName}.lic";

  licenseEnvFor =
    hostName:
    let
      licenseFile = licenseFileFor hostName;
    in
    {
      XILINXD_LICENSE_FILE = licenseFile;
      XILINX_LICENSE_FILE = licenseFile;
      LM_LICENSE_FILE = licenseFile;
    };

  getHost =
    hostName:
    hosts.${hostName} or (throw "doctor-cluster-xilinx: no Xilinx host facts for ${hostName}");

  getFpga =
    hostName: fpgaName:
    let
      host = getHost hostName;
    in
    host.fpgas.${fpgaName}
      or (throw "doctor-cluster-xilinx: host ${hostName} has no FPGA named ${fpgaName}");

  getDefaultFpga =
    hostName:
    let
      host = getHost hostName;
    in
    getFpga hostName host.defaultFpga;

  hostFpgaEnvShellFragment =
    let
      hostCases = lib.concatStringsSep "\n" (
        lib.flatten (
          lib.mapAttrsToList (
            hostName: host:
            lib.mapAttrsToList (fpgaName: fpga: ''
              ${hostName}:${fpgaName})
                export FPGA_BDF=${lib.escapeShellArg fpga.bdf}
                ${lib.optionalString (
                  fpga ? partHint
                ) "export FPGA_PART_HINT=${lib.escapeShellArg fpga.partHint}"}
                ${lib.optionalString (
                  fpga ? targetPlatform
                ) "export TARGET_PLATFORM=${lib.escapeShellArg fpga.targetPlatform}"}
                ${lib.optionalString (
                  fpga ? jtagTarget
                ) "export FPGA_JTAG_TARGET=${lib.escapeShellArg fpga.jtagTarget}"}
                ${lib.optionalString (
                  fpga ? hwServerPort
                ) "export COYOTE_NIX_HW_SERVER_PORT=${lib.escapeShellArg fpga.hwServerPort}"}
                ;;
            '') host.fpgas
          ) hosts
        )
      );
    in
    ''
      doctor_cluster_xilinx_host="''${DOCTOR_CLUSTER_XILINX_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)}"
      doctor_cluster_xilinx_fpga="''${FDEV_NAME:-}"
      case "$doctor_cluster_xilinx_host:$doctor_cluster_xilinx_fpga" in
      ${hostCases}
      esac
      unset doctor_cluster_xilinx_host doctor_cluster_xilinx_fpga
    '';

  mkXilinxContext =
    {
      pkgs,
      system ? pkgs.stdenv.hostPlatform.system,
      xilinxName ? "xilinx-shell",
      runScript ? "bash",
    }:
    let
      doctorPackages = doctor-cluster-config.packages.${system} or { };
    in
    {
      inherit
        xilinxShareRoot
        targetPlatforms
        boards
        hosts
        licenseFileFor
        licenseEnvFor
        getHost
        getFpga
        getDefaultFpga
        hostFpgaEnvShellFragment
        ;

      xilinxShell = mkXilinxShell {
        inherit
          pkgs
          system
          xilinxName
          runScript
          ;
      };

      driverKernels = mkDriverKernels { inherit pkgs system; };
      packages = doctorPackages;
      nixosConfigurations = doctor-cluster-config.nixosConfigurations;
    };
in
{
  inherit
    xilinxShareRoot
    targetPlatforms
    boards
    hosts
    mkXilinxShell
    mkDriverKernels
    licenseFileFor
    licenseEnvFor
    getHost
    getFpga
    getDefaultFpga
    hostFpgaEnvShellFragment
    mkXilinxContext
    ;
}
