{
  description = "Eqty Infrastructure Helm Charts";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs:
    (inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        deps = with pkgs; [
          azure-cli
          kubernetes-helm
          kubectl
          yq
        ];
      in
      {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = deps;
          };

        };
      }
    ));
}

