#!${bash}/bin/bash
set -euo pipefail

usage="
Usage: devtools-${name} python
       devtools-${name} pip
       devtools-${name} activate
       devtools-${name} deactivate
       devtools-${name} (-h | --help)

Modes:
  python       Forward the remaining arguments to the python
               interpreter bundled by this configuration.
  pip          Forward the remaining arguments to pip
               ('python -m pip').
  activate     Emit shell commands that add this environment's
               interpreter and modules to PATH. Intended to be
               evaluated by the shell, e.g.:

                 eval \"\$(devtools/${name} activate)\"

  deactivate   Undo the changes made by 'activate'.
"

# Mode flags, pre-initialized so that they are always defined; the
# 'docopts' invocation below assigns the real values.
python=false
pip=false
activate=false
deactivate=false

# Parse the mode (the first argument only) with docopts; the
# remaining arguments are forwarded verbatim to the selected mode.
# Passing only the first argument avoids 'docopts' trying to
# interpret the forwarded arguments as options of its own.
eval "$(${docopts}/bin/docopts -h "$usage" : "''${1:-}")"
shift

if [ "$python" = "true" ]; then
  exec ${python-env}/bin/python "$@"
fi

if [ "$pip" = "true" ]; then
  exec ${python-env}/bin/python -m pip "$@"
fi

if [ "$activate" = "true" ]; then
  echo "export ${backup-var}=\"''${PATH-}\""
  echo "export PATH=${python-env}/bin:''${PATH}"
  exit 0
fi

if [ "$deactivate" = "true" ]; then
  echo "if [[ -n \"''${${backup-var}-}\" ]]; then"
  echo "  export PATH=\"''${${backup-var}}\""
  echo "  unset ${backup-var}"
  echo "fi"
  exit 0
fi