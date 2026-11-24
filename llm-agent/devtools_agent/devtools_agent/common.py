"""
Shared helpers of the agent programs: both the agent manager and
the agent itself need to inspect the branches of the agent git
repository and to canonicalize their names into systemd templated
unit instance names, and to set up their logging in a consistent
way (see 'configure_logging').
"""

import logging
import subprocess
import sys

from devtools_flake.agent import env


# Attributes always present on a stdlib LogRecord; used to isolate
# the 'extra' fields attached by callers for structured logging, so
# the formatter below can render only those (and not the stock ones).
_STANDARD_LOG_FIELDS = frozenset({
    "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
    "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
    "created", "msecs", "relativeCreated", "thread", "threadName",
    "processName", "process", "taskName", "message", "asctime",
})


class _StructuredFormatter(logging.Formatter):
    """
    A formatter that appends the structured 'extra' fields of a log
    record (those not part of the stdlib LogRecord) as 'key=value'
    pairs. The structured data is therefore both attached to the
    record (for handlers that consume it directly, such as journald
    fields or a JSON formatter) and visible in plain text output —
    which is how the systemd services' stdout reaches journald.
    """
    def format(self, record):
        message = super().format(record)
        extra = {
            key: value
            for key, value in record.__dict__.items()
            if key not in _STANDARD_LOG_FIELDS
        }
        if not extra:
            return message
        pairs = " ".join(
            f"{key}={value!r}" for key, value in sorted(extra.items())
        )
        return f"{message} {pairs}"


def configure_logging():
    """
    Configure the root logger for the agent programs. Both the agent
    manager and the agent itself log to standard output (captured by
    journald for the systemd services) with a level prefix; any
    structured 'extra' fields passed to the log call are appended to
    the line by '_StructuredFormatter'.

    This is the single place that sets up logging so the two programs
    share the same logging approach (the agent program's tool-usage
    logging relies on it).
    """
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_StructuredFormatter("%(levelname)s %(name)s: %(message)s"))
    logging.basicConfig(
        level=logging.INFO,
        handlers=[handler],
    )


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