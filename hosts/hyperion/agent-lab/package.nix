{
  lib,
  rustPlatform,
  buzzSrc,
}:

rustPlatform.buildRustPackage {
  pname = "buzz-cli";
  version = "0.5.11-248b9d1";
  src = buzzSrc;

  cargoHash = "sha256-7BQWBpHdmwt9BAbDlsEmk4PIYkeRDZwYIck3kgIJolo=";
  cargoBuildFlags = [
    "-p"
    "buzz-cli"
  ];

  # Upstream's workspace-wide integration suites require its full development
  # stack. The selected release binary is exercised by its own build.
  doCheck = false;

  installPhase = ''
    runHook preInstall
    releaseDir=target/x86_64-unknown-linux-gnu/release
    install -Dm755 "$releaseDir/buzz" $out/bin/buzz
    runHook postInstall
  '';

  meta = {
    description = "Buzz CLI for the Hyperion Hermes gateways";
    homepage = "https://github.com/block/buzz";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
