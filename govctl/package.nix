{ lib, python3Packages }:

let
  pyprojectToml = builtins.fromTOML (builtins.readFile ./pyproject.toml);
in
python3Packages.buildPythonApplication {
  pname = "govctl";
  inherit (pyprojectToml.project) version;
  pyproject = true;

  src = ./.;

  build-system = with python3Packages; [
    hatchling
  ];

  dependencies = with python3Packages; [
    click
    cryptography
    pyyaml
    rich
  ];

  meta = {
    description = "CLI tool for generating Guardian Platform Helm values";
    license = lib.licenses.mit;
    mainProgram = "govctl";
  };
}
