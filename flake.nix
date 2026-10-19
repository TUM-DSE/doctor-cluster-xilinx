{
  description = "Doctor cluster Xilinx site facts for FPGA/Coyote projects";

  inputs = {
    doctor-cluster-config.url = "git+ssh://git@github.com/TUM-DSE/doctor-cluster-config.git";
    nixpkgs.follows = "doctor-cluster-config/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      doctor-cluster-config,
      ...
    }:
    let
      doctorXilinxLib = import ./lib { inherit doctor-cluster-config; };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        doctorContext = doctorXilinxLib.mkXilinxContext { inherit pkgs system; };
      in
      {
        checks = {
          eval-context = pkgs.runCommand "doctor-cluster-xilinx-eval-context" { } ''
            ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
              test "${doctorContext.xilinxShareRoot}" = "/share/xilinx"
              test "${builtins.concatStringsSep " " doctorContext.targetPlatforms}" = "ultrascale_plus versal"
              test "${doctorContext.boards.u280.xilinxVersion}" = "2023.2"
              test "${doctorContext.boards.u280.simXilinxVersion}" = "2022.2"
              test "${doctorContext.boards.v80.xilinxVersion}" = "2025.1"
              test "${doctorContext.hosts.rose.fpgas.u280.bdf}" = "0000:e1:00.0"
              test "${doctorContext.hosts.rose.fpgas.v80.bdf}" = "0000:c1:00.0"
              test "${doctorContext.hosts.amy.fpgas.v80.bdf}" = "0000:81:00.0"
              test "${builtins.toString (doctorContext.hosts.clara.fpgas ? v80)}" = ""
              stale_hardware_facts() {
                export FPGA_BDF=stale-bdf FPGA_PART_HINT=stale-part TARGET_PLATFORM=stale-target
                export COYOTE_NIX_TARGET_PLATFORM=stale-coyote-target COYOTE_NIX_PLATFORM=stale-platform
                export FPGA_JTAG_TARGET=stale-jtag
                export COYOTE_NIX_HW_SERVER_PORT=9991 COYOTE_NIX_CS_SERVER_PORT=9992 HW_SERVER_PORT=9993
              }
              assert_hardware_facts_cleared() {
                test -z "''${FPGA_BDF:-}" && test -z "''${FPGA_PART_HINT:-}"
                test -z "''${TARGET_PLATFORM:-}" && test -z "''${COYOTE_NIX_TARGET_PLATFORM:-}"
                test -z "''${COYOTE_NIX_PLATFORM:-}"
                test -z "''${FPGA_JTAG_TARGET:-}" && test -z "''${COYOTE_NIX_HW_SERVER_PORT:-}"
                test -z "''${COYOTE_NIX_CS_SERVER_PORT:-}" && test -z "''${HW_SERVER_PORT:-}"
              }
              (
                export DOCTOR_CLUSTER_XILINX_HOST=amy FDEV_NAME=v80
                stale_hardware_facts
                ${doctorContext.hostFpgaEnvShellFragment}
                test "$FDEV_NAME" = v80
                test "$FPGA_BDF" = "0000:81:00.0"
                test "$FPGA_PART_HINT" = "xcv80"
                test "$TARGET_PLATFORM" = "versal"
                test -z "''${FPGA_JTAG_TARGET:-}"
                test -z "''${COYOTE_NIX_HW_SERVER_PORT:-}"
                test -z "''${COYOTE_NIX_CS_SERVER_PORT:-}"
                test -z "''${HW_SERVER_PORT:-}"
                test -z "''${COYOTE_NIX_TARGET_PLATFORM:-}"
                test -z "''${COYOTE_NIX_PLATFORM:-}"
              )
              (
                export DOCTOR_CLUSTER_XILINX_HOST=clara FDEV_NAME=v80
                stale_hardware_facts
                ${doctorContext.hostFpgaEnvShellFragment}
                assert_hardware_facts_cleared
                test "$FDEV_NAME" = v80
              )
              (
                export DOCTOR_CLUSTER_XILINX_HOST=unknown-host FDEV_NAME=u280
                stale_hardware_facts
                ${doctorContext.hostFpgaEnvShellFragment}
                assert_hardware_facts_cleared
                test "$FDEV_NAME" = u280
              )
              (
                export DOCTOR_CLUSTER_XILINX_HOST=amy FDEV_NAME=unknown-board
                stale_hardware_facts
                ${doctorContext.hostFpgaEnvShellFragment}
                assert_hardware_facts_cleared
                test "$FDEV_NAME" = unknown-board
              )
              (
                export DOCTOR_CLUSTER_XILINX_HOST=rose FDEV_NAME=u280
                stale_hardware_facts
                ${doctorContext.hostFpgaEnvShellFragment}
                test "$FPGA_BDF" = "0000:e1:00.0"
                test "$FPGA_PART_HINT" = "xcu280"
                test "$TARGET_PLATFORM" = "ultrascale_plus"
                test "$FPGA_JTAG_TARGET" = "217702174005A"
                test "$COYOTE_NIX_HW_SERVER_PORT" = 3121
                test -z "''${COYOTE_NIX_CS_SERVER_PORT:-}"
                test -z "''${COYOTE_NIX_TARGET_PLATFORM:-}"
                test -z "''${COYOTE_NIX_PLATFORM:-}"
                test -z "''${HW_SERVER_PORT:-}"
              )
              test "${doctorContext.hosts.rose.fpgas.u280.jtagTarget}" = "217702174005A"
              test "${doctorContext.hosts.rose.fpgas.u280.hwServerPort}" = "3121"
              test "${doctorContext.hosts.rose.fpgas.u280.simXilinxVersion}" = "2022.2"
              test "${doctorContext.hosts.rose.fpgas.v80.jtagTarget}" = "XFL1EZVSAG4SA"
              test "${doctorContext.hosts.rose.fpgas.v80.hwServerPort}" = "3122"
              grep -q 'rose:v80)' <<'EOF'
              ${doctorContext.hostFpgaEnvShellFragment}
              EOF
              grep -q 'FPGA_JTAG_TARGET' <<'EOF'
              ${doctorContext.hostFpgaEnvShellFragment}
              EOF
            ''}
            touch $out
          '';

          xilinx-shell-lscpu = pkgs.runCommand "doctor-cluster-xilinx-shell-lscpu" { } ''
            ${doctorContext.xilinxShell}/bin/xilinx-shell -c '
              test -x /usr/bin/lscpu
              test "$(command -v lscpu)" = /usr/bin/lscpu
              /usr/bin/lscpu > /tmp/lscpu.txt
              grep -q "^Architecture:" /tmp/lscpu.txt
              grep -q "^CPU(s):" /tmp/lscpu.txt
              /usr/bin/lscpu --help >/dev/null
            '
            touch $out
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nixfmt-rfc-style
          ];
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    )
    // {
      lib = doctorXilinxLib;
    };
}
