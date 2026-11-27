# Todo: this module should allow configuring python environments. It should follow the same
# style as the modules in this repository such that multiple configurations can be defined
# simultaneosuly. The configuration should allow the following:
# * Expose an option to define packages that will be bundled with the python environment. It should
#   be a function that becomes an argument to the 'withPackages' function. Furthermore, multiple
#   declarations must be meregable by calling all functions and concatenating the result.
# * It should expose an application, named like the configuration. It should have the following modes:
#   - python: Forwards the remaining arguments to the python intepreter
#   - pip: Forwards the remaining arguments to pip
#   - activate/deactivate: Adds the relevant items, such as PATH items, to the shell so the interpreter and modules
#     bundled by this configuration become available in the shell
# * It should expose a nixos module that can be added to a sandbox container. See the 'examples/flakeModue.nix'
#   for a concrete example of the desired usage. This module should add the python iterpreter and any applications
#   exposed by the python modules to the system path.
