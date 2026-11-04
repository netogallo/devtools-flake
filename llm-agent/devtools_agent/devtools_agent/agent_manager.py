"""
The agent manager program. It runs inside the agent VM as a systemd
service and keeps one 'agent-run@<canonical branch name>.service'
instance per branch of the agent git repository.
"""

import subprocess
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

from devtools_flake.agent import env

# The signal emitted by the 'post-receive' hook of the agent git
# repository on every push. The value of the signal is the hash of
# the latest commit of the pushed branch.
SIGNAL_INTERFACE = "org.devtools_flake.events.git"
SIGNAL_NAME = "notify_push"


def canonicalize_branch_name(branch):
    """
    Canonicalize a branch name into a name that is acceptable as the
    instance name of a systemd templated unit: slashes and
    underscores are replaced and the name is lowercased.
    """
    return branch.replace("/", ".").replace("_", "-").lower()


def list_branches():
    """
    List all the branches of the agent git repository, as defined by
    'devtools_flake.agent.env.repo_path'.
    """
    result = subprocess.run(
        [env.git, "for-each-ref", "--format=%(refname:short)", "refs/heads/"],
        capture_output=True,
        text=True,
        cwd=env.repo_path,
    )
    if result.returncode != 0:
        sys.exit(f"error listing branches of '{env.repo_path}': {result.stderr}")
    return [line for line in result.stdout.splitlines() if line]


def unit_name(canonical):
    return f"agent-run@{canonical}.service"


def unit_active(canonical):
    """
    Whether the instance of the templated agent unit for the
    canonicalized branch name is running. Running instances are
    ignored when reconciling: they also monitor the push signal and
    will pick up updates on their branch themselves.
    """
    return subprocess.run(
        ["systemctl", "is-active", "--quiet", unit_name(canonical)],
    ).returncode == 0


def start_unit(canonical):
    subprocess.run(
        ["systemctl", "start", unit_name(canonical)],
        check=True,
    )


def reconcile():
    """
    Start an agent instance for every branch that does not have a
    running instance, ignoring the branches that already do.
    """
    for branch in list_branches():
        canonical = canonicalize_branch_name(branch)
        if unit_active(canonical):
            print(f"instance already running for branch '{branch}', ignoring")
            continue
        print(f"starting agent instance for branch '{branch}'")
        start_unit(canonical)


def on_notify_push(*args):
    """
    A push notification: the value of the signal is the hash of the
    latest commit of the pushed branch. Reconcile the agent instances
    with the branches of the repository.
    """
    print(f"received push notification: {args}")
    reconcile()


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    bus.add_signal_receiver(
        on_notify_push,
        dbus_interface=SIGNAL_INTERFACE,
        signal_name=SIGNAL_NAME,
    )
    # Reconcile once at startup so that a reboot of the VM (or a
    # restart of the manager) restarts the agents for all branches.
    reconcile()
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()