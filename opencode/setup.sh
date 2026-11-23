usage="
Usage:
  setup-${opencode-container-name} nat activate
  setup-${opencode-container-name} nat deactivate
  setup-${opencode-container-name} (-h | --help)

Modes:
  nat activate      Ensure the host is configured to run the
                    container: ip forwarding is active and the
                    firewall forwards the container's traffic
                    between the container's bridge
                    ('${bridge}') and the system's network
                    interfaces.
  nat deactivate    Undo the configuration created by
                    'setup activate'.
"

# The mode flags read below, pre-initialized so that they are
# always defined; docopts assigns the real values below.
nat=false
activate=false
deactivate=false

# Parse the mode flags; docopts turns the usage text into the
# 'run', 'setup', 'activate' and 'deactivate' shell variables.
eval "$(docopts -h "$usage" : "$@")"

# Idempotently ensure ('-C' checks the rule, '-I' inserts it at
# the top of the chain) or remove ('-D' deletes it) an
# iptables/ip6tables rule.
ensure-rule() {
  local tool=$1
  shift
  if ! "$tool" -C "$@" > /dev/null 2>&1; then
    "$tool" -I "$@"
  fi
}

remove-rule() {
  local tool=$1
  shift
  if "$tool" -C "$@" > /dev/null 2>&1; then
    "$tool" -D "$@"
  fi
}

# The setup requires root priviledges as it modifies system
# settings such as routing tables and kernel parameters.
if [ "$(id -u)" != "0" ]; then
  echo "Error: this program must be run as root." >&2
  exit 1
fi

if [[ "$nat" = "true" && "$activate" = "true" ]]; then
  echo "Enabling ip forwarding..."
  sysctl -w net.ipv4.ip_forward=1
  sysctl -w net.ipv6.conf.all.forwarding=1

  echo "Ensuring firewall rules for the container's bridge '${bridge}'..."
  # Let the container's traffic leave through the host's
  # interfaces and let the replies come back in.
  ensure-rule iptables FORWARD -i ${bridge} -j ACCEPT
  ensure-rule iptables FORWARD -o ${bridge} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  # Masquerade the container's traffic so that replies find
  # their way back through the host.
  ensure-rule iptables POSTROUTING -t nat -s ${ipv4-subnet} ! -o ${bridge} -j MASQUERADE
fi

if [[ "$nat" = "true" && "$deactivate" = "true" ]]; then
  echo "Removing firewall rules for the container's bridge '${bridge}'..."
  remove-rule iptables FORWARD -i ${bridge} -j ACCEPT
  remove-rule iptables FORWARD -o ${bridge} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  remove-rule iptables POSTROUTING -t nat -s ${ipv4-subnet} ! -o ${bridge} -j MASQUERADE

  echo "Disabling ip forwarding..."
  sysctl -w net.ipv4.ip_forward=0
fi
