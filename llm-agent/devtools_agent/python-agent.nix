{
  buildPythonPackage,
  python,
  langchain,
  langchain-openai,
  agent-env,
  ...
}:
let
  sources = ./.;
in
  buildPythonPackage {
    pname = "devtools_agent";
    version = "0.0.1";
    format = "other";
    dontUnpack = true;
    dontUsePythonRemoveTestsDir = true;
    propagatedBuildInputs = [ python-box ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/${python.sitePackages}
      cp -rL ${sources}/. $out/${python.sitePackages}/
      runHook postInstall
    '';
  };
