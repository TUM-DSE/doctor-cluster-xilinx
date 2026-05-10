{
  description = "Doctor cluster Xilinx site facts for FPGA/Coyote projects";

  inputs = {
    doctor-cluster-config.url = "path:/home/theo/doctor-cluster-config";
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
        checks.eval-context = pkgs.runCommand "doctor-cluster-xilinx-eval-context" { } ''
          ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
            test "${doctorContext.xilinxShareRoot}" = "/share/xilinx"
            test "${builtins.concatStringsSep " " doctorContext.targetPlatforms}" = "ultrascale_plus versal"
            test "${doctorContext.boards.u280.xilinxVersion}" = "2023.2"
            test "${doctorContext.boards.u280.simXilinxVersion}" = "2022.2"
            test "${doctorContext.boards.v80.xilinxVersion}" = "2025.1"
            test "${doctorContext.hosts.rose.fpgas.u280.bdf}" = "0000:c1:00.0"
            test "${doctorContext.hosts.rose.fpgas.u280.simXilinxVersion}" = "2022.2"
            grep -q 'rose:v80)' <<'EOF'
            ${doctorContext.hostFpgaEnvShellFragment}
            EOF
          ''}
          touch $out
        '';

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
