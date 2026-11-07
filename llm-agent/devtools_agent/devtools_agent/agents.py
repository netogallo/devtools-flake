"""
Abstractions over the functionality to connect to an agent and
send messages to it. All environment variables of the agent use
the 'DEVTOOLS_LLM_AGENT_' prefix; the 'DEVTOOLS_LLM_AGENT_MODE'
variable selects the implementation offered by this module:

- 'main': the real agent, implemented with langchain; it connects
  to the llm provider configured for the agent.
- 'test': an object that just provides mock responses to specific
  test prompts, used to test the flow around the agent without
  connecting to a real llm.

Both implementations have the ability to accept the tools defined
externally (by the caller), so that the agent machinery can be
exercised with any set of tools.
"""

import os
import sys
from types import SimpleNamespace

from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent

ENV_PREFIX = "DEVTOOLS_LLM_AGENT_"

# Environment variable selecting the agent implementation
# (one of MODE_MAIN, MODE_TEST).
MODE_ENV_VAR = ENV_PREFIX + "MODE"

MODE_MAIN = "main"
MODE_TEST = "test"

# The dummy task given to the agent. The test implementation
# provides a mock response for this prompt.
TASK_PROMPT = (
    "Summarize the changes that happened in the last commit "
    "(HEAD) of this repository. Use the git tools to inspect "
    "the commit and its diff, and list the files in the "
    "working directory if that helps."
)


class MainAgent:
    """
    The main agent implementation: a langchain react agent
    connected to the llm provider, exposing the externally
    defined tools to the model.
    """

    def __init__(self, tools):
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

        self.tools = tools
        self.agent = create_react_agent(llm, tools)

    def invoke(self, prompt):
        """
        Send a message to the agent, returning the messages of
        the resulting conversation.
        """
        result = self.agent.invoke({"messages": [("user", prompt)]})
        return result["messages"]


class TestAgent:
    """
    The test agent implementation: an object that provides mock
    responses to specific test prompts. It accepts the tools like
    the main implementation but ignores them: no real llm is
    contacted.
    """

    def __init__(self, tools):
        self.tools = tools
        self.responses = {
            TASK_PROMPT: "mock response: summary of the last commit of the repository.",
        }

    def invoke(self, prompt):
        """
        Return the mock response for the given test prompt. There
        is no mock response for unknown prompts.
        """
        try:
            response = self.responses[prompt]
        except KeyError:
            sys.exit(f"test agent: no mock response for prompt: {prompt!r}")
        return [SimpleNamespace(content=response)]


def select_agent(tools):
    """
    Select the agent implementation as configured by the
    'DEVTOOLS_LLM_AGENT_MODE' environment variable, defaulting to
    the main implementation. The tools (defined externally by the
    caller) are passed to the selected implementation.
    """
    mode = os.environ.get(MODE_ENV_VAR, MODE_MAIN)
    if mode == MODE_MAIN:
        return MainAgent(tools)
    if mode == MODE_TEST:
        return TestAgent(tools)
    sys.exit(
        f"error: unknown {MODE_ENV_VAR} '{mode}' "
        f"(expected '{MODE_MAIN}' or '{MODE_TEST}')"
    )