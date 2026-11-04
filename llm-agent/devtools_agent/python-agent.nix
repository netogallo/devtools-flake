{
  buildPythonPackage,
  python,
  langchain,
  langchain-openai,
  langgraph,
  dbus-python,
  pygobject3,
  agent-env,
  ...
}:
let
  sources = ./devtools_agent;
in
  buildPythonPackage {
    pname = "devtools_agent";
    version = "0.0.1";
    format = "other";
    dontUnpack = true;
    dontUsePythonRemoveTestsDir = true;
    propagatedBuildInputs = [
      agent-env
      langchain
      langchain-openai
      langgraph
      dbus-python
      pygobject3
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/${python.sitePackages}
      cp -rL ${sources} $out/${python.sitePackages}/devtools_agent
      runHook postInstall
    '';
  }