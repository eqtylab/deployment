{ lib, python3Packages }:

python3Packages.buildPythonApplication {
  pname = "govctl";
  version = "0.1.0";
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
    description = "CLI tool for generating Governance Platform Helm values";
    license = lib.licenses.mit;
    mainProgram = "govctl";
  };
}
