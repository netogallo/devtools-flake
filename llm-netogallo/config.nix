/** This file holds the flake configuration spec for the
*   'llm-netogallo' mode for Aider. This mode provides the
*   following:
*   - Divide your workflow in tasks.
*   - Save the conversation with the LLM within your repository,
*     organized by task.
*   - The saved conversations can then be used to further generate
*     content. As an example, a technical report can easily be
*     generated from that material describing what was implemented.
*/
{ self, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib) mkPerSystemOption;
  flake-config = config;
  llm-netogallo-spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable this tool for a particular name.
        '';
        default = false;
      };
      working-directory = mkOption {
        type = types.str;
        description = ''
          The working directory. If specified as relative,
          it will be relative to the CWD where the llm tool
          is launched. This directory will be used for the
          following pruposes:
            * Store the llm context/history
            * Store the chat history with the llm
            * Store information about the current task
        '';
        default = "journal";
      };
      task-branch-prefix = mkOption {
        type = types.nullOr types.str;
        description = ''
          The prefix in the name of the git branch that activates
          the 'task mode' of the llm tool. When working in 'task'
          mode, the conversation with the llm will be saved to
          the working directory and the task description will
          be injected to the llm context.
        '';
        default = null;
      };
    };
  };
  perSystem = { pkgs, ... }:
  let
    inherit (
      pkgs.callPackage
      ./setup.nix
      { inherit (flake-config.development-tools) llm-netogallo; }
    ) apps;
  in
    { config = { inherit apps; }; }
  ;
in
  {
    options = {
      development-tools.llm-netogallo = mkOption {
        type = types.attrsOf llm-netogallo-spec;
        description = ''
          This allows configuring the aider llm programming
          tool with the setup used by netogallo. Each value
          will become an individual configuration.
        '';
        default = {};
      };
      perSystem = mkPerSystemOption perSystem;
    };
  }
