"""
The agent program. It is run inside the agent VM by a templated
systemd unit ('agent-run@<canonical branch name>.service'), in a
working directory prepared by the unit's script.
"""

import argparse
import os
import subprocess
import sys

from langchain_core.tools import tool

from devtools_flake.agent import env

from devtools_agent.agents import select_agent, task_prompt
from devtools_agent.common import (
    canonicalize_branch_name,
    list_branches,
)


def main():
    # --- The systemd template's instance parameter ---
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--unit-id",
        required=True,
        help="The systemd template parameter: the canonicalized name of the branch to run the agent on.",
    )
    args = parser.parse_args()

    # The working directory has been set by the unit's script
    # before launching the agent.
    work_dir = os.getcwd()

    # --- Check the repository exists, cloning it if not ---
    if not os.path.isdir(".git"):
        subprocess.run(
            [env.git, "clone", env.repo_path, "."],
            check=True,
            cwd=work_dir,
        )

    # --- Determine the branch for this unit id ---
    # List all the branches of the repository, canonicalize each
    # name (as done by agent_manager.py) and select the branch
    # whose canonicalized name matches the unit id.
    branches = list_branches()
    branch = next(
        (b for b in branches if canonicalize_branch_name(b) == args.unit_id),
        None,
    )
    if branch is None:
        sys.exit(
            f"error: no branch canonicalizes to the unit id '{args.unit_id}' "
            f"(branches: {branches})"
        )

    # --- Record the current revision ---
    # The current HEAD is recorded before updating the working
    # directory so the agent can be asked to summarize the changes
    # since then. There may be no commits yet (for instance on the
    # first run after cloning an empty branch), in which case there is
    # nothing to record.
    recorded_rev = subprocess.run(
        [env.git, "rev-parse", "--verify", "--quiet", "HEAD"],
        capture_output=True,
        text=True,
        cwd=work_dir,
    ).stdout.strip() or None

    # --- Update the working directory to the latest commit ---
    # The latest commit available in 'env.repo_path' is always checked
    # out. There are two cases:
    # 1) Changes are applied on top of existing changes, an ordinary
    #    fast-forward should suffice.
    # 2) Git history has diverged. In this case, the history of
    #    'env.repo_path' overwrites the history in this directory.
    # In both cases fetching from 'origin' (the clone source, i.e.
    # 'env.repo_path') and resetting the branch hard to the fetched
    # tip yields the desired result: a fast-forward when possible, an
    # overwrite of any divergent local history otherwise.
    subprocess.run([env.git, "fetch", "origin"], check=True, cwd=work_dir)
    subprocess.run([env.git, "checkout", branch], check=True, cwd=work_dir)
    subprocess.run(
        [env.git, "reset", "--hard", f"origin/{branch}"],
        check=True,
        cwd=work_dir,
    )

    # --- Determine the last revision to summarize from ---
    # If the recorded revision is an ancestor of the new HEAD the
    # branch fast-forwarded, and the changes since that revision are
    # summarized. Otherwise the branch diverged (or there was no
    # previous revision): default to HEAD~1 so the agent summarizes the
    # latest commit only.
    if recorded_rev is not None and subprocess.run(
        [env.git, "merge-base", "--is-ancestor", recorded_rev, "HEAD"],
        cwd=work_dir,
    ).returncode == 0:
        last_revision = recorded_rev
    else:
        last_revision = "HEAD~1"

    # --- Agent tools ---
    @tool
    def list_files(directory: str) -> str:
        """List the files in the given directory."""
        return "\n".join(sorted(os.listdir(directory)))

    @tool
    def run_git(command: str) -> str:
        """Run a read-only git command in the working directory.

        Only inspecting git subcommands (show, diff, log, status)
        are allowed.
        """
        parts = command.split()
        allowed = ["show", "diff", "log", "status"]
        if not parts or parts[0] not in allowed:
            return f"error: only these git subcommands are allowed: {allowed}"
        result = subprocess.run(
            [env.git] + parts,
            capture_output=True,
            text=True,
            cwd=work_dir,
        )
        return result.stdout or result.stderr

    # --- The agent: connect and send the task message ---
    agent = select_agent([list_files, run_git])
    messages = agent.invoke(task_prompt(last_revision))

    for message in messages:
        content = getattr(message, "content", None)
        if content:
            print(content)


if __name__ == "__main__":
    main()
