"""
Todo:
This file exposes a main program which should do the following:
1. Use dbus to subscribe to signals matchiing: "org.devtools_flake.events.git.notify_push". This signals
    will be triggered by the git commit hook defined in "../setup.nix".
2. When a singal is received, this program should check the "devtools_flake.agent.env.repo_path"
    and get a list of all the git branches that exist for that repository.
3. The branch names should be canonalized to something that is acceptable as the name of a
    systemd templated unit.
4. For each branch name, check which instances of '<canonical branch name>@agent-run' service
    are running. Those instances can be ignored as they will also monitor the "org.devtools_flake.events.git.notify_push"
    signal for updates.
5. Instances which are not running should be started.
"""
