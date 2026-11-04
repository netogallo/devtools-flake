"""
Todo:
UPdate this file as it should do the following:
1. This main function can assume that the cwd has been correctly set before launch.
2. It accepts a "--unit-id" parameter which is the systemd template parameter.
3. Check if the git repository exits, if not, create one by cloning 'devtools_flake.agent.env.repo_path'.
4. Determine the branch, this is done by:
    i. List all the branches in the repository
    ii. Compute the canonicalized name of each branch (as done by agent_manager.py).
    iii. Select the branch whose canonicalized name matched the "--unit-id" parameter.
    iiii. Fail if there is no match.
5. Checkout the branch. Use the git executable defined by 'devtools_flake.agent.env.git'.
6. Run the agent task as before.
"""

import os
import sys

from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langgraph.prebuilt import create_react_agent

from devtools_flake.agent import env

def main():
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
        import subprocess
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

if __name__ == "main":
    main()
