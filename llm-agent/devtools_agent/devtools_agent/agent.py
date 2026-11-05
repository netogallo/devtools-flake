"""
The agent program. It is run inside the agent VM by a templated
systemd unit ('agent-run@<canonical branch name>.service'), in a
working directory prepared by the unit's script.
"""

import argparse
import os
import subprocess
import sys

from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent

from devtools_flake.agent import env

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

    # --- Checkout the branch ---
    subprocess.run([env.git, "checkout", branch], check=True, cwd=work_dir)

    # --- Configuration (injected by the systemd service) ---
    base_url = os.environ["OPENAI_BASE_URL"]
    model = os.environ["OPENAI_MODEL"]
    user = os.environ["AGENT_USER"]

    # --- API key: read at runtime from the shared config dir ---
    key_file = os.path.join(os.environ["AGENT_KEYS_DIR"], "users", user + ".key")
    with open(key_file) as f:
        api_key = f.read().strip()

    # --- LLM client via the provider's OpenAI-compatible API ---
    llm = ChatOpenAI(
        model=model,
        base_url=base_url,
        api_key=api_key,
    )

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

    tools = [list_files, run_git]

    # --- The deep agent, given the dummy task ---
    agent = create_react_agent(llm, tools)
    result = agent.invoke({
        "messages": [
            ("user",
             "Summarize the changes that happened in the last commit "
             "(HEAD) of this repository. Use the git tools to inspect "
             "the commit and its diff, and list the files in the "
             "working directory if that helps.")
        ]
    })

    for message in result["messages"]:
        content = getattr(message, "content", None)
        if content:
            print(content)


if __name__ == "__main__":
    main()
