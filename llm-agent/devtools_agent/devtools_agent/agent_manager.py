"""
The agent manager program. It runs inside the agent VM as a systemd
service and keeps one 'agent-run@<canonical branch name>.service'
instance per branch of the agent git repository.
"""

import logging
import subprocess
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

from devtools_flake.agent import env

from devtools_agent.common import (
    canonicalize_branch_name,
    list_branches,
)

log = logging.getLogger(__name__)


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
    """
    Start the agent instance for the canonicalized branch name.
    Failure to start an instance is logged; it does not crash the
    manager, which keeps processing the remaining branches.
    """
    try:
        subprocess.run(
            ["systemctl", "start", unit_name(canonical)],
            check=True,
        )
    except subprocess.CalledProcessError as error:
        log.error(
            "failed to start agent instance for canonical branch name '%s': %s",
            canonical,
            error,
        )


def reconcile():
    """
    Start an agent instance for every branch that does not have a
    running instance, ignoring the branches that already do.
    """
    for branch in list_branches():
        canonical = canonicalize_branch_name(branch)
        if unit_active(canonical):
            log.info("instance already running for branch '%s', ignoring", branch)
            continue
        log.info("starting agent instance for branch '%s'", branch)
        start_unit(canonical)


def on_notify_push(*args):
    """
    A push notification: the value of the signal is the hash of the
    latest commit of the pushed branch. Reconcile the agent instances
    with the branches of the repository.
    """
    log.info("received push notification: %s", args)
    reconcile()


def main():
    # For the time being the manager logs to standard output.
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stdout,
        format="%(levelname)s %(name)s: %(message)s",
    )

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    bus.add_signal_receiver(
        on_notify_push,
        dbus_interface=env.push_signal.interface,
        signal_name=env.push_signal.name,
    )
    # Reconcile once at startup so that a reboot of the VM (or a
    # restart of the manager) restarts the agents for all branches.
    reconcile()
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()