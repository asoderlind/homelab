{
  mnemosyneSrc,
  python312Packages,
}:

let
  mnemosyneMemory = python312Packages.buildPythonPackage {
    pname = "mnemosyne-memory";
    version = "3.15.1";
    pyproject = true;
    src = mnemosyneSrc;

    build-system = with python312Packages; [
      setuptools
      wheel
    ];
    dependencies = with python312Packages; [
      fastembed
      pyyaml
      sqlite-vec
    ];

    pythonImportsCheck = [ "mnemosyne" ];
    doCheck = false;
  };
in
python312Packages.buildPythonPackage {
  pname = "mnemosyne-hermes";
  version = "0.5.0";
  pyproject = true;
  src = mnemosyneSrc + "/integrations/hermes";

  build-system = with python312Packages; [
    setuptools
    wheel
  ];
  dependencies = with python312Packages; [
    mnemosyneMemory
    pyyaml
  ];

  pythonImportsCheck = [ "mnemosyne_hermes" ];
  doCheck = false;

  passthru.mnemosyneMemory = mnemosyneMemory;
}
