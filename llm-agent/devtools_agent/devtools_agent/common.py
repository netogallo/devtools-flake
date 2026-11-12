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


def git(*args, cwd=None, check=True, capture=False):
    """
    Run a git command using the binary configured by 'env.git',
    returning the completed process.

    This is the single place through which the agent programs invoke
    git, so that the binary path (injected by the NixOS configuration
    via 'env.git'), the working directory and the error handling are
    kept consistent across the codebase (see 'list_branches' and the
    agent program's checkout/update logic).

    When 'check' is true (the default) a non-zero exit status aborts
    the program with a descriptive message, mirroring the behavior of
    the previous ad-hoc 'subprocess.run(..., check=True)' calls. When
    'capture' is true, stdout and stderr are captured as text and
    returned on the process; otherwise they are inherited from the
    caller (so, for instance, the agent's own 'run_git' tool can keep
    streaming its output).
    """
    result = subprocess.run(
        [env.git, *args],
        cwd=cwd,
        capture_output=capture,
        text=capture,
    )
    if check and result.returncode != 0:
        sys.exit(
            f"error running git {list(args)} in '{cwd or env.repo_path}': "
            f"{result.stderr}"
        )
    return result


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
    result = git(
        "-c",
        f"safe.directory={env.repo_path}",
        "for-each-ref",
        "--format=%(refname:short)",
        "refs/heads/",
        cwd=env.repo_path,
        capture=True,
        # A failure here is reported with the repository-specific
        # message below rather than the generic one from 'git()'.
        check=False,
    )
    if result.returncode != 0:
        sys.exit(f"error listing branches of '{env.repo_path}': {result.stderr}")
    return [line for line in result.stdout.splitlines() if line]