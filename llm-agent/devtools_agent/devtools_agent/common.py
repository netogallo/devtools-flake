"""
Shared helpers of the agent programs: both the agent manager and
the agent itself need to inspect the branches of the agent git
repository and to canonicalize their names into systemd templated
unit instance names.
"""

import subprocess
import sys

from devtools_flake.agent import env


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

    The manager service runs as root while the repository is owned
    by the 'git' user, so a git 'safe.directory' exception must be
    configured for the invocation or git fails with 'detected
    dubious ownership in repository'. The exception is harmless for
    the agent instances, which run as the 'git' user.
    """
    result = subprocess.run(
        [
            env.git,
            "-c",
            f"safe.directory={env.repo_path}",
            "for-each-ref",
            "--format=%(refname:short)",
            "refs/heads/",
        ],
        capture_output=True,
        text=True,
        cwd=env.repo_path,
    )
    if result.returncode != 0:
        sys.exit(f"error listing branches of '{env.repo_path}': {result.stderr}")
    return [line for line in result.stdout.splitlines() if line]