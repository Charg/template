{
  description = "Copier template for Charg projects: development toolchain and CI environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            # Rendering and updating projects.
            pkgs.copier
            # Task runner and git hooks.
            pkgs.just
            pkgs.prek
            # Lint (hack/lint.sh), the same set a generated project gets.
            pkgs.actionlint
            pkgs.nixfmt
            pkgs.shellcheck
            pkgs.yamllint
            pkgs.zizmor
            # Used by the scripts directly.
            pkgs.git
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
