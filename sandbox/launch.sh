#!${bash}/bin/bash
set -e

usage="
Usage: launch-${sandbox-name} run [--delete]
       launch-${sandbox-name} setup nat activate
       launch-${sandbox-name} setup nat deactivate
       launch-${sandbox-name} (-h | --help)

Modes:
  run                   Boot the nspawn container.
  setup nat activate    Ensure the host is configured to run the
                        container: ip forwarding is active and the
                        firewall forwards the container's traffic
                        between the container's bridge
                        ('${bridge}') and the system's network
                        interfaces.
  setup nat deactivate  Undo the configuration created by
                        'setup activate'.

Options:
  --delete              (run only) Delete the container's root
                        filesystem before booting, so the next boot
                        starts from a clean root. The persistent home
                        directory (kept outside of the root) is
                        preserved.
"

# The mode flags read below, pre-initialized so that they are
# always defined; docopts assigns the real values below.
run=false
setup=false
delete=false

# shellcheck disable=SC1091
source ${source-config}

# Parse the mode flags; docopts turns the usage text into the
# 'run', 'setup', 'activate', 'deactivate' and 'delete' shell
# variables.
eval "$(${docopts}/bin/docopts -h "$usage" : "$@")"

if [ "$run" = "true" ]; then
  # When '--delete' is set, remove the container's root filesystem
  # before booting so that the next boot starts from a clean root.
  # The persistent home directory (kept outside of the root, see
  # 'container-home-dir') is preserved. Removal requires root as
  # the container's root files are owned by root.
  if [ "$delete" = "true" ]; then
    echo "Removing the container's root filesystem at '${container-root-dir}'..."
    sudo rm -rf "${container-root-dir}"
  fi

  # The container keeps the user's home directory outside of the
  # root filesystem so that it survives rebuilds; make sure it
  # exists before booting (the home bind mount below would
  # otherwise fail).
  mkdir -p "${container-home-dir}"

  # The container needs ip forwarding to reach the network
  # through the host.
  if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "Warning: ip forwarding is not active on the host." >&2
    echo "Run '$0 setup nat activate' to configure the host system." >&2
  fi
  exec sudo ${nspawn}
fi

if [ "$setup" = "true" ]; then
  shift
  sudo "${setup-app}" "$@"
fi
