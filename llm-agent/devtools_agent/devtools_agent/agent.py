"""
The agent program. It is run inside the agent VM by a templated
systemd unit ('agent-run@<canonical branch name>.service'), in a
working directory prepared by the unit's script.
"""

import argparse
import os
import pty
import select
import subprocess
import sys
import tempfile

from langchain_core.tools import tool

from devtools_flake.agent import env

from devtools_agent.agents import select_agent, task_prompt
from devtools_agent.common import (
    canonicalize_branch_name,
    git,
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
        git("clone", env.repo_path, ".", cwd=work_dir)

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
    recorded_rev = (
        git(
            "rev-parse",
            "--verify",
            "--quiet",
            "HEAD",
            cwd=work_dir,
            check=False,
            capture=True,
        ).stdout.strip()
        or None
    )

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
    git("fetch", "origin", cwd=work_dir)
    git("checkout", branch, cwd=work_dir)
    git("reset", "--hard", f"origin/{branch}", cwd=work_dir)

    # --- Determine the last revision to summarize from ---
    # If the recorded revision is an ancestor of the new HEAD the
    # branch fast-forwarded, and the changes since that revision are
    # summarized. Otherwise the branch diverged (or there was no
    # previous revision): default to HEAD~1 so the agent summarizes the
    # latest commit only.
    if recorded_rev is not None and git(
        "merge-base",
        "--is-ancestor",
        recorded_rev,
        "HEAD",
        cwd=work_dir,
        check=False,
    ).returncode == 0:
        last_revision = recorded_rev
    else:
        last_revision = "HEAD~1"

    # --- Agent tools ---
    # The agent runs in a sandbox and is used to edit code. It is
    # given tools to view files (with line numbers, paged), to edit
    # files (whole-file overwrite, a targeted unique replacement,
    # and a unified-diff patch), and to run arbitrary shell
    # commands. Because it runs in a sandbox no guardrails are
    # enforced on the shell commands.
    @tool
    def list_files(directory: str) -> str:
        """List the files in the given directory."""
        return "\n".join(sorted(os.listdir(directory)))

    @tool
    def view_file(path: str, start_line: int = 1, end_line: int = 0) -> str:
        """View a file's contents with line numbers.

        Lines are 1-indexed. 'start_line' defaults to 1; 'end_line'
        defaults to 0, meaning 'to the end of the file'. Each line is
        returned as '<n>: <line>', prefixed by the total number of
        lines in the file. Use a line range to page through large
        files instead of loading them whole.
        """
        with open(path) as f:
            lines = f.read().splitlines()
        total = len(lines)
        start = max(1, start_line)
        end = total if end_line <= 0 else min(end_line, total)
        if start > end:
            return f"({total} lines total) (empty range)"
        body = "\n".join(
            f"{i}: {line}"
            for i, line in zip(range(start, end + 1), lines[start - 1:end])
        )
        return f"({total} lines total)\n{body}"

    @tool
    def write_file(path: str, content: str) -> str:
        """Write the entire contents of a file, creating or replacing it.

        Use this to create new files or to rewrite a file in full.
        For targeted edits prefer 'str_replace' or 'apply_patch',
        which are cheaper and less error-prone.
        """
        with open(path, "w") as f:
            f.write(content)
        return f"wrote {len(content)} characters to {path}"

    @tool
    def str_replace(path: str, old_str: str, new_str: str) -> str:
        """Replace a unique snippet of text in a file.

        'old_str' must occur exactly once in the file; an error is
        returned if it is not found or if it occurs more than once
        (include more surrounding context to make it unique). The
        surrounding content is preserved verbatim.
        """
        with open(path) as f:
            content = f.read()
        occurrences = content.count(old_str)
        if occurrences == 0:
            return f"error: old_str not found in {path}"
        if occurrences > 1:
            return (
                f"error: old_str occurs {occurrences} times in {path}; "
                "add more surrounding context to make it unique"
            )
        with open(path, "w") as f:
            f.write(content.replace(old_str, new_str))
        return f"replaced 1 occurrence in {path}"

    @tool
    def apply_patch(patch: str) -> str:
        """Apply a unified-diff patch to the working tree.

        The patch must be in unified diff format (as produced by
        'git diff' or 'diff -u'). It is applied to the working tree,
        not the git index, using 'git apply'. On failure the error
        output of 'git apply' is returned.
        """
        with tempfile.NamedTemporaryFile(
            "w", suffix=".patch", delete=False
        ) as f:
            f.write(patch)
            patch_path = f.name
        try:
            result = subprocess.run(
                [env.git, "apply", "--whitespace=nowarn", patch_path],
                capture_output=True,
                text=True,
                cwd=work_dir,
            )
        finally:
            os.unlink(patch_path)
        if result.returncode != 0:
            return result.stderr or result.stdout or "patch did not apply"
        return "patch applied"

    @tool
    def run_shell(command: str) -> str:
        """Run an arbitrary shell command in the working directory.

        stdout and stderr are merged and returned interleaved in the
        order they are written, on a whole-line basis — matching what
        would appear on an interactive terminal. The agent runs in a
        sandbox, so any command may be run; no guardrails are enforced.
        If the command exits non-zero, its exit status is appended.
        """
        # A pseudo-terminal is used so that the child sees a tty and
        # line-buffers its output, and so that stdout and stderr are
        # merged at the point of writing rather than captured into two
        # separate streams. This reproduces the on-screen ordering of
        # an interactive shell.
        master, slave = pty.openpty()
        proc = subprocess.Popen(
            command,
            shell=True,
            stdout=slave,
            stderr=slave,
            stdin=subprocess.DEVNULL,
            cwd=work_dir,
        )
        os.close(slave)
        chunks = []
        while True:
            # Wait for output, but periodically poll the child so that
            # a command which produces no output (or which blocks)
            # does not hang the tool forever once the child has exited.
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    data = os.read(master, 4096)
                except OSError:
                    break  # pty EOF: the slave was closed
                if not data:
                    break
                chunks.append(data)
            elif proc.poll() is not None:
                break
        os.close(master)
        proc.wait()
        output = b"".join(chunks).decode("utf-8", errors="replace")
        if proc.returncode != 0:
            output += f"\n[exit status {proc.returncode}]\n"
        return output or "(no output)"

    # --- The agent: connect and send the task message ---
    agent = select_agent(
        [list_files, view_file, write_file, str_replace, apply_patch, run_shell]
    )
    messages = agent.invoke(task_prompt(last_revision))

    for message in messages:
        content = getattr(message, "content", None)
        if content:
            print(content)


if __name__ == "__main__":
    main()
