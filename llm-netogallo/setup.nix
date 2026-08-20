{ llm-netogallo, lib, pkgs, ... }:
let
  run-llm-application = name: { working-directory, task-branch-prefix, ... }:
  let
    is-enabled = if task-branch-prefix == null then "false &&" else "true &&";
    task-preamble = pkgs.writeText "task-preamble" ''
      The user is working on a task which has been defined in '$TASK_FILE'. This
      file will be read into the context for your reference. Your job is
      to assist the user with any request related tho the task.
    '';
  in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [ git aider-chat nano gettext docopts ];
      text = ''
        set -xue -o pipefail
        new_task=false
        aider_args=()
        eval "$(docopts -h - : "$@" <<DOCOPTS
        [PROGRAM]: A tool to organize workflows with LLM assistance
        Usage:
          [PROGRAM] [--new-task] [--aider-args=<args>...]
          [PROGRAM] (-h | --help)
        Options:
          --new-task       Start a new task.
          --aider-args=<args>  Arguments to pass to aider.
          -h, --help       Show this help.
        DOCOPTS
        )"

        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

        # Check if we are not in a task branch. Launch aider
        # normally in that case
        if ${is-enabled} [[ "$CURRENT_BRANCH" != "${task-branch-prefix}"* ]]; then
        	aider "$@"
        	exit 0
        fi
        
        LLM_DIR="journal/$CURRENT_BRANCH"
        mkdir -p "$LLM_DIR"

        # The session dir is meant to be used to store
        # the chat history with the LLM
        LLM_SESSION_CONTEXT_DIR="$LLM_DIR/session-contexts"
        mkdir -p "$LLM_SESSION_CONTEXT_DIR"

        LLM_TASKS_DIR="$LLM_DIR/tasks"
        mkdir -p "$LLM_TASKS_DIR"

        LLM_CONTROL_DIR="$LLM_DIR/control"
        mkdir -p "$LLM_CONTROL_DIR"

        LLM_CURRENT_TASK_FILE="$LLM_CONTROL_DIR/current_task.txt"

        if [[ ! -f "$LLM_CURRENT_TASK_FILE" || "$new_task" == "true" ]]; then
          read -rp "Starting a new task. What is the task name? " task_name
          echo "$task_name" > "$LLM_CURRENT_TASK_FILE"
        fi

        LLM_TASK=$(cat "$LLM_CURRENT_TASK_FILE")
        LLM_ACTIVE_TASK_FILE="$LLM_TASKS_DIR/$LLM_TASK"

        if [[ ! -f "$LLM_ACTIVE_TASK_FILE" ]]; then
          echo "Describe the task $task_name here..." > "$LLM_ACTIVE_TASK_FILE"
          nano "$LLM_ACTIVE_TASK_FILE"
        fi

        mkdir -p "$LLM_SESSION_CONTEXT_DIR/$LLM_TASK"
        TASK_INPUT_FILE=$(mktemp)

        cat "${task-preamble}" \
          | (TASK_FILE="$LLM_ACTIVE_TASK_FILE" envsubst) \
          > "$TASK_INPUT_FILE"
        
        aider \
          --read "$TASK_INPUT_FILE" \
          --read "$LLM_ACTIVE_TASK_FILE" \
        	--llm-history-file "$LLM_SESSION_CONTEXT_DIR/$LLM_TASK/llm.history" \
        	--chat-history-file "$LLM_SESSION_CONTEXT_DIR/$LLM_TASK/session.md" "''${aider_args[@]}"
      '';
    }
  ;
  to-llm-app = name: spec:
  let
    application = run-llm-application name spec;
  in 
    {
      name = "devtools/${name}";
      value = {
        type = "app";
        program = "${application}/bin/${application.NIX_MAIN_PROGRAM}";
      };
    }
  ;
in
  {
    apps = lib.mapAttrs' to-llm-app llm-netogallo;
  }
