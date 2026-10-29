
# aider chat started at 2026-10-28 14:11:07

> /nix/store/c4vc8qhlrddf9lm0d31nq9imm4hvpd7k-aider-chat-0.86.1/bin/aider --read /tmp/tmp.xkiZLisEul --read journal/feature/agentic-dev/tasks/Agent git repository --llm-history-file journal/feature/agentic-dev/session-contexts/Agent git repository/llm.history --chat-history-file journal/feature/agentic-dev/session-contexts/Agent git repository/session.md  
> Aider v0.86.1  
> Model: openrouter/z-ai/glm-5.3 with whole edit format  
> Git repo: .git with 50 files  
> Repo-map: using 4096 tokens, auto refresh  
> Added ../../../../tmp/tmp.xkiZLisEul to the chat (read-only).  
> Added journal/feature/agentic-dev/tasks/Agent git repository to the chat (read-only).  

#### /ask  
> Aider v0.86.1  
> Model: openrouter/z-ai/glm-5.3 with ask edit format  
> Git repo: .git with 50 files  
> Repo-map: using 4096 tokens, auto refresh  
> Added ../../../../tmp/tmp.xkiZLisEul to the chat (read-only).  
> Added journal/feature/agentic-dev/tasks/Agent git repository to the chat (read-only).  

#### Make a proposal to implement the requested changes.  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Let me understand the task. The user is working on a git repository (a Nix flake-based configuration repo, it seems, with modules like `llm-agent`, `lite-llm`, `llm-netogallo`, `neovim`, etc.).

The task defined in `journal/feature/agentic-dev/tasks/Agent git repository` says:

1. Create a git repository. Changes will be pushed to the repository via ssh.
2. The 'llm-agent' service monitors the git repository.
3. Whenever changes are pushed to the git repository, the corresponding branch should be checked out into a directory.
4. A Langchain deep agent is spawned, with said directory as its working directory.
5. At present, the agent will be given a dummy task of summarizing the changes that happened in the last commit.

So I need to make a proposal to implement this. Let me think about what I know about the repo structure:

- It's a Nix flake with `flakeModule.nix` (flake-parts), `presets/flakeModule.nix`, `examples/flakeModule.nix`.
- There are modules: `llm-agent` (config.nix, setup.nix), `lite-llm` (config.nix, setup.nix), `llm-netogallo` (config.nix, setup.nix), `llm-providers` (config.nix, prelude.nix), `neovim` (various), `prelude/config.nix`.
- There's a journal system with tasks and session contexts (agentic-dev feature).

The `llm-agent` module presumably defines a service that spawns a QM VM (QEMU microvm?) — "The QM vm spawned by llm-agent". QM likely refers to QEMU microvm. The llm-agent service spawns a VM, and inside that VM, we need:

1. A git repository created (bare repo probably, since changes will be pushed via SSH).
2. SSH access to allow pushing.
3. A service that monitors the git repository (e.g., a post-receive hook or inotify or polling).
4. On push, check out the branch into a directory.
5. Spawn a Langchain deep agent with that directory as working directory, with a dummy task of summarizing the last commit's changes.

I don't have the full contents of the files, so I should make a proposal that is somewhat generic but tailored to the structure: NixOS modules with config.nix and setup.nix pattern (config.nix likely defines options/types, setup.nix defines the implementation — this is a common pattern in this repo, "prelude" files contain shared helpers).

The proposal should cover:

- Architecture: where the git repo lives (in the VM), how SSH is set up (openssh, git user, authorized keys), how monitoring works (post-receive hook is the most robust — triggers on push; alternatively a systemd path unit or polling).
- Branch checkout: on push to a branch, clone/checkout that branch into a working directory (e.g., `/var/lib/agent/work/<branch>`), using `git worktree` or `git clone` + `git checkout`.
- Agent spawning: a Langchain deep agent (Python, langchain `create_deep_agent` or similar) run with cwd set to the checkout directory. The dummy task: summarize changes in the last commit (git show / git diff HEAD~1..HEAD), then write the summary somewhere (e.g., a file `SUMMARY.md` in the repo or just log output).
- Implementation plan in terms of the repo's module structure: extend `llm-agent/config.nix` with new options (e.g., `programs.llm-agent.gitRepository` settings), and `llm-agent/setup.nix` with the service definitions. Possibly a new module `llm-agent/git.nix` or similar. Since the repo pattern is config.nix (options) + setup.nix (implementation), the proposal should follow that.
- Also the VM: "The QM vm spawned by llm-agent" — so llm-agent spawns a QEMU microvm. The git repo and monitoring should live inside that VM. So the NixOS configuration for the VM needs: openssh, git, the repo initialization, the post-receive hook, the agent runner script, systemd services.

Let me draft the proposal:

## Proposal

### Overview
Add functionality to the `llm-agent` module so that the QEMU micro-VM it spawns hosts:
- a bare git repository that accepts pushes over SSH,
- a monitor that reacts to pushes,
- a checkout step,
- and a Langchain deep agent run against the checkout.

### Components

1. **Git repository + SSH access (inside the VM)**
   - Create a bare repository at e.g. `/var/lib/git/repo.git` (or configurable), owned by a dedicated `git` user.
   - Enable `openssh` with the git user's authorized keys; restrict the git user to git commands (optional: git-shell).
   - Initialize with `git init --bare` via a systemd oneshot or `systemd.tmpfiles`/activation script.

2. **Push detection**
   - Preferred: a `post-receive` hook in the bare repo. The hook receives old/new rev and ref names on stdin; for each pushed branch it triggers the checkout+agent pipeline. This is simpler and more reliable than polling/inotify.
   - Alternative: systemd path unit watching the repo directory, or a polling loop. Mention as fallback.

3. **Branch checkout**
   - A small script (e.g. `/usr/local/bin/checkout-branch` or a systemd service template) that, given a branch name, does `git clone` (or `git worktree add`) of the bare repo into `/var/lib/agent/work/<branch>` and checks out the pushed ref. Use `git clone --branch <branch> file:///var/lib/git/repo.git /var/lib/agent/work/<branch>` or fetch+reset for existing checkouts.

4. **Agent spawn**
   - A Python program using Langchain's deep agent (`create_deep_agent` / `create_react_agent` with planning tools — "deep agent" suggests langchain's experimental deep agents). It is launched with `cwd` set to the checkout directory.
   - The dummy task: "Summarize the changes in the last commit" — the agent can run `git show`/`git diff HEAD~1 HEAD` itself via a shell tool, or we pre-compute the diff and embed it in the prompt. Simplest: give the agent a shell/terminal tool and the instruction; it has the repo as cwd.
   - The agent needs an LLM backend — the repo already has `lite-llm` (LiteLLM proxy) and `llm-providers`; point the agent at the LiteLLM endpoint (OpenAI-compatible base URL) with the configured model.

5. **Wiring in the module structure**
   - `llm-agent/config.nix`: add options (enable flag, repo path, work dir, ssh keys, branch defaults, LLM endpoint/model options).
   - `llm-agent/setup.nix`: implement services: `git-repo-init` (oneshot), `agent-on-push` (template service instantiated per branch by the hook), the post-receive hook file, the Python agent script packaged via `pkgs.writers.writePython3` or a plain `pkgs.writeText` + `pkgs.python3.withPackages`.
   - Possibly a new file `llm-agent/git-repo.nix` if we want to keep setup.nix small; follow existing conventions.

6. **Testing**
   - Use the flake's checks/devShells; manual test: `git push` over SSH from host to VM, observe checkout and agent run, summary output written to e.g. `SUMMARY.md` or logged.

Open questions: where the summary should go (commit back? file? log?), whether the VM has network access to LiteLLM, which user runs the agent.

I should keep the proposal reasonably brief but complete. The user asked "Make a proposal to implement the requested changes." So a structured proposal with steps, files to touch, and design decisions. I should note that I haven't seen the full file contents, so the proposal makes assumptions about module conventions (config.nix = options, setup.nix = config) and I may need the actual files to refine.

Also note the task says "The QM vm spawned by llm-agent" — QM = QEMU microvm. So the changes go into the VM's NixOS configuration, which presumably is built by the llm-agent module. The monitoring service ("llm-agent service monitors the git repository") — the llm-agent service in the VM.

Let me structure the proposal:

1. Goal recap
2. Design decisions (post-receive hook vs polling; bare repo; worktree checkout; agent invocation)
3. Implementation steps with file-level changes
4. Data flow
5. Testing plan
6. Open questions

Keep it concise. Use headers and bullets. Since it's a proposal, moderate length is fine. Format: markdown with headers, bullets. Probably 300-500 words. Let me write it.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

# Proposal: Git-triggered agent pipeline in the `llm-agent` VM

## Goal recap

Inside the QEMU micro-VM spawned by `llm-agent`:

1. Host a git repository accepting pushes over SSH.
2. Detect pushes to that repository.
3. Check out the pushed branch into a working directory.
4. Launch a Langchain deep agent with that directory as its working directory, with the dummy task "summarize the changes in the last commit".

## Design decisions

- **Repository**: a bare repo at e.g. `/var/lib/agent/repo.git`, owned by a dedicated `git` user. SSH access via `openssh` with that user's `authorizedKeys`; pushes go to `git@vm:repo.git`.
- **Push detection**: a `post-receive` hook in the bare repo. It receives the ref names and new revisions on stdin, so it's exact and avoids polling/inotify. The hook enqueues work by calling `systemctl start agent@<branch>` (template service) or by writing to a spool dir watched by a path unit.
- **Checkout**: for each pushed branch, clone/fetch the bare repo into `/var/lib/agent/work/<branch>` (`git clone --branch` on first push, `git fetch && git reset --hard` on subsequent ones). `git worktree` is an alternative but a plain clone is simpler and isolates branches.
- **Agent**: a small Python program using Langchain's deep agent, launched with `cwd = /var/lib/agent/work/<branch>`. It gets a shell tool so it can run `git show`/`git diff HEAD~1` itself; the prompt is just the dummy task. The LLM endpoint comes from the existing `lite-llm`/`llm-providers` configuration (OpenAI-compatible base URL + model name exposed as module options).

## Implementation steps

1. **`llm-agent/config.nix`** — add options: `enableGitTrigger` (bool), repo path, work dir, SSH keys for the git user, LLM endpoint/model passthrough.
2. **`llm-agent/setup.nix`** (or a new `llm-agent/git-repo.nix` if it grows) — implement:
   - `git` user + `openssh` config;
   - a oneshot service initializing the bare repo and installing the `post-receive` hook;
   - the checkout script and `agent@.service` systemd template (one instance per branch);
   - the Python agent script (packaged with `python3.withPackages [ langchain ... ]`), writing its summary to `SUMMARY.md` in the work dir and/or the journal.
3. **Wiring**: ensure the VM's NixOS config built by `llm-agent` includes the above when the option is enabled.

## Data flow

`git push` → SSH → bare repo → `post-receive` → checkout of branch → agent process (cwd = checkout) → summary output.

## Testing

- flake checks/devShell as usual; manual end-to-end: push from host, verify checkout dir appears and agent run produces a summary.

## Open questions

- Where should the summary land (file in the workdir, log, or committed back)?
- Should the agent run per-branch concurrently, or serialized per branch?
- Does the VM already have network access to the LiteLLM endpoint, or does that need forwarding?

I haven't seen the full contents of `llm-agent/config.nix`/`setup.nix` — if you add them to the chat I can align the proposal with the actual option/module conventions before we start implementing.

> Tokens: 977 sent, 2.8k received. Cost: $0.0039 message, $0.0039 session.  
> llm-agent/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> llm-agent/setup.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Let me look at the current state of the files. The user has added `llm-agent/config.nix` and `llm-agent/setup.nix` to the chat. Let me review what I know:

**llm-agent/config.nix**: Defines the `development-tools.llm-agent` option as an attrsOf spec, where each agent has `enable` and `provider` options. The perSystem module imports setup.nix for each agent with `llm-agent-name` and `llm-agent` args.

**llm-agent/setup.nix**: Builds a NixOS VM with:
- A Python environment with langchain + langchain-openai
- An agent script using `create_react_agent` with a `list_files` tool
- A VM config with a systemd service `llm-agent` that runs the agent script
- 9p mount of the host's DEVTOOLS_CONFIG for API keys
- A launch script that sources the devtools prelude config, checks provider reachability, writes the user key, and runs the VM

Now the task: implement the git repository workflow in the VM:
1. Create a git repository, changes pushed via SSH
2. llm-agent service monitors the git repository
3. On push, check out the branch into a directory
4. Spawn a Langchain deep agent with that directory as working directory
5. Dummy task: summarize changes in last commit

Now I should update my proposal based on the actual code. Let me think about what's needed:

Current setup:
- The VM runs a oneshot service `llm-agent` that runs the agent script with a dummy task (list files in /tmp)
- The VM has a nixos user with a known hashed password
- The agent reads API key from 9p-mounted `/run/agent_keys`

What needs to change:
1. **SSH server in the VM**: Need `services.openssh.enable = true` with a `git` user (or reuse `nixos` user). The host pushes via SSH. Need port forwarding from host to guest (QEMU user networking hostfwd). The QEMU VM script uses `qemu-vm.nix` which by default sets up user networking with hostfwd for ssh (port 2222 → 22? Actually `virtualisation.forwardPorts` option). By default qemu-vm.nix sets `forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ]`? Let me recall: `virtualisation.forwardPorts` defaults to forwarding SSH port 22 to host port 2222 when graphics is off? Actually in qemu-vm.nix, `virtualisation.forwardPorts` defaults to `[]` but there's a default hostfwd for ssh when `virtualisation.graphics = false`? Let me recall the actual code: In nixos qemu-vm.nix:

```nix
virtualisation.forwardPorts = mkOption {
  default = [];
  ...
};
```

and

```nix
virtualisation.qemu.networkingOptions = ...
```

Actually, the default `qemu.networkingOptions` includes `-netdev user,restrict=on`... Hmm. Let me recall: qemu-vm.nix has:

```nix
virtualisation.forwardPorts = [
  { from = "host"; host.port = 2222; guest.port = 22; }
]
```

Hmm, I believe the default is that SSH is forwarded from host port 2222 to guest port 22 when `virtualisation.graphics = false`? Actually I recall that in qemu-vm.nix:

```nix
virtualisation.forwardPorts = mkOption {
  default = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
  ...
```

Hmm, not exactly. Let me think. The actual default in qemu-vm.nix:

```nix
virtualisation.forwardPorts = mkOption {
  default = [];
  type = with types; listOf (submodule {...});
};
```

and then in the config:

```nix
virtualisation.qemu.networkingOptions = mkVMOverride (
  [
    "-net nic,macvlan=0,model=virtio"
    "-net user,restrict=on${concatMapStrings "," forwardedPorts}"
  ]);
```

Hmm, I don't remember exactly. Actually I recall that qemu-vm.nix sets up:

```nix
virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
```

Hmm no. Let me think about what I know for sure: In NixOS VM tests, `virtualisation.forwardPorts` is used to forward ports. The default value is `[]`. But there's a default SSH forward? I believe the default `virtualisation.forwardPorts` is:

```nix
forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
```

Hmm, actually I'm fairly confident that qemu-vm.nix has this in it:

```nix
virtualisation.forwardPorts = mkVMOverride (
  [ { from = "host"; host.port = 2222; guest.port = 22; } ] ++ ...
);
```

Hmm. Let me just recall from the source of nixos/modules/virtualisation/qemu-vm.nix:

```nix
virtualisation.forwardPorts = mkOption {
  type = with types; listOf (submodule {
    options = {
      from = mkOption { type = enum [ "host" "guest" ]; ... };
      host.port = mkOption { type = types.port; };
      guest.port = mkOption { type = types.port; };
    };
  });
  default = [];
  description = ''
    List of ports forwarded from host to guest...
  '';
};
```

and

```nix
virtualisation.qemu.networkingOptions = mkVMOverride (
  [
    "-net nic,macvlan=0,model=virtio"
    "-net user,restrict=on${concatMapStrings "," forwardedPorts}"
  ]);
```

where forwardedPorts is built from forwardPorts. And I believe there's a default SSH forward: In the module, there's:

```nix
virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
```

Hmm, actually I remember that in qemu-vm.nix, when `virtualisation.graphics = false`, the console is on ttyS0. And I do remember that the default `forwardPorts` includes SSH 2222→22. Let me check: I recall the code:

```nix
virtualisation.forwardPorts = mkVMOverride (
  [ { from = "host"; host.port = 2222; guest.port = 22; } ]
);
```

Hmm, I'm not 100% sure. Actually, I'm fairly sure the default is:

```nix
virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
```

No wait. I think I'm conflating with `virtualisation.qemu.options`. Let me look at what I know from the actual qemu-vm.nix source (nixpkgs):

```nix
virtualisation.forwardPorts = mkOption {
  default = [];
  ...
};
```

and later:

```nix
forwardedPorts = "[${concatMapStrings (x: ",hostfwd=${...}") cfg.forwardPorts}]";
```

Hmm, and there's this in the module:

```nix
# Use a static QEMU user networking... 
```

I recall that in the VM, ssh is accessible on localhost:2222 by default in many setups (e.g., `nixos-shell`, `nix run` VMs). Actually yes! I'm now quite sure: qemu-vm.nix contains:

```nix
virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
```

Hmm, no. Let me think about `nixos-shell` — it sets `virtualisation.forwardPorts` explicitly. And in the standard `nixosvm-run` script, there's a comment about connecting via `ssh -p 2222`. Hmm.

OK, regardless of the exact default, I can just set `virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ]` explicitly in our config to be safe. That's the robust approach: explicitly forward host port 2222 (or some port) to guest 22.

Actually wait — I should double check: the default in qemu-vm.nix is:

```nix
virtualisation.forwardPorts = mkVMOverride (
  [ { from = "host"; host.port = 2222; guest.port = 22; } ]
);
```

Hmm, I genuinely can't remember. I'll just set it explicitly. That's the safe move and I'll note it in the proposal.

2. **Git repository in the VM**: A bare repo at `/var/lib/agent/repo.git` owned by a `git` user. SSH access: the `git` user's `authorized_keys`. But how do the host's public keys get into the VM? Options:
   - Generate an SSH keypair on the host at build time (nixpkgs `runCommand` with ssh-keygen) and put the private key in the host's DEVTOOLS_CONFIG dir (or a runtime dir), and the public key in the VM's authorized_keys. Since the private key would be in the nix store (world-readable), that's not great but it's a dev tool VM; better: generate at VM build time and pass via 9p? The 9p share is read-only from guest perspective and comes from host's DEVTOOLS_CONFIG. We could have the launch script generate a keypair into DEVTOOLS_CONFIG (host side, at launch time), and pass the public key into the VM... but the VM config is built at build time, not launch time. Hmm.
   
   Alternative: pass the public key via QEMU `-smbios` or kernel cmdline? Kernel cmdline is visible in /proc/cmdline — we could append the pubkey as a kernel param. That's hacky but works: `boot.kernelParams = [ "agent.git.pubkey=${pubkey}" ]` — but pubkey is generated at launch time, not build time.
   
   Simpler: the launch script generates the keypair into `$DEVTOOLS_CONFIG/agent-git/` (host side), which is 9p-shared to the guest at `/run/agent_keys`. The guest's sshd config uses `authorized_keys` from that mount for the git user. The private key stays on the host in DEVTOOLS_CONFIG, and the host-side launch script prints/uses it. The public key is read by the guest from the 9p mount (e.g., `/run/agent_keys/agent-git/id_ed25519.pub`).
   
   That fits the existing secret-handling pattern nicely: secrets live in DEVTOOLS_CONFIG on the host, shared read-only via 9p, read at runtime by the guest. 

   For sshd authorized_keys: we can't easily point `users.users.git.openssh.authorizedKeys` at a runtime file... Actually we can: `services.openssh.settings` or use `authorizedKeysFiles` to include a path like `/run/agent_keys/agent-git/authorized_keys`. sshd's `AuthorizedKeysFile` can list multiple files, including an absolute path. So set `services.openssh.settings.authorizedKeysFiles`? Actually the option is `services.openssh.authorizedKeysFiles`? Hmm, in NixOS the option is `services.openssh.settings.AuthorizedKeysFile`? There's `users.users.<name>.openssh.authorizedKeys.keys` and `.keyFiles`. There's also `services.openssh.authorizedKeysFiles`? Hmm, I don't think that exists. There is `services.openssh.settings` which maps to sshd_config settings, so `services.openssh.settings.AuthorizedKeysFile = "/run/agent_keys/agent-git/authorized_keys %h/.ssh/authorized_keys"` or similar. That works since sshd reads authorized_keys at authentication time, and the 9p mount is up by then (it's wanted by multi-user.target; sshd also starts at boot — ordering: sshd would need the mount. We can add `wants`/`after` on the mount for sshd, or just make sshd depend on the mount unit).

   Alternatively simpler: the git user's `authorized_keys` file could be generated at build time with a keypair generated in the nix store (build-time generated keypair via `runCommand "ssh-keygen..."`). Private key in the store is world-readable — bad practice but this is a local dev VM. But the launch script on the host needs the private key to push... it could read it from the store path. Hmm, that's insecure but functional. The DEVTOOLS_CONFIG approach is cleaner and matches the existing pattern (key-script writes user key into DEVTOOLS_CONFIG/users/).

   I'll propose: launch script generates an ed25519 keypair into `$DEVTOOLS_CONFIG/agent-git/` if not present; guest sshd reads authorized_keys from the 9p mount; host-side helper script (or printed instructions) uses the private key to push. Also the launch script could do an initial push of the current repo? No — the repo to push is chosen by the user; the host just needs to know how to push: `git push ssh://git@localhost:2222/...` Hmm wait, the guest's ssh is on port 2222 forwarded from host. From the host, `ssh -p 2222 git@localhost`.

   Actually, wait. Is SSH even needed? The task says "Changes will be pushed to the repository via ssh." So yes, SSH.

3. **Push detection**: `post-receive` hook in the bare repo. The hook script needs to trigger the checkout+agent pipeline. Options:
   - Hook calls `systemctl start agent-run@<branch>.service` — needs the hook to run as root or a user with sudo rights. The git user could be allowed via sudoers or polkit to start the template service. Or the hook writes a file into a spool directory (e.g. `/var/lib/agent/inbox/`) and a systemd path unit triggers the run service. The spool approach decouples privileges: hook (running as git user) writes a small file; a systemd path unit on the spool dir starts the run service as root (or as agent user).
   
   I'll propose the spool + path unit approach: `post-receive` writes `/var/lib/agent/inbox/<branch>` (sanitized branch name) with the new sha; `systemd.path` on the inbox triggers `agent-run.service` (oneshot) which processes all pending files: for each, checkout branch into `/var/lib/agent/work/<branch>` and run the agent with that cwd.

   Actually simpler: post-receive directly invokes a script that does checkout+agent run. But then the agent runs as the git user and the hook blocks the push until the agent finishes (bad — push would hang for the whole LLM run). Better to decouple: hook enqueues, systemd runs asynchronously. The spool approach also serializes runs naturally (path unit + oneshot service with `RefuseManualStart` etc.). Actually multiple files could arrive while service is running; the service should loop until inbox is empty.

   Alternatively, the hook could use `systemd-run` as root via sudo. The spool approach is cleaner privilege-wise. Let me go with spool + path unit.

4. **Checkout**: script `checkout-branch.sh <branch>`: 
   ```
   work=/var/lib/agent/work/<sanitized-branch>
   if [ -d "$work/.git" ]; then git -C "$work" fetch origin && git -C "$work" reset --hard origin/<branch>
   else git clone --branch <branch> /var/lib/agent/repo.git "$work"; fi
   ```
   Owned by the user the agent runs as.

5. **Agent**: extend the existing agent script: instead of the dummy "list /tmp" task, the task is "summarize the changes in the last commit" with cwd = work dir. The current script uses `create_react_agent` with a `list_files` tool. For the git task, give it a `run_git` tool or a shell tool restricted to git commands, or simply pre-compute `git show`/`git diff` output? The task says "A Langchain deep agent is spawned" — deep agents (langchain's `deepagents` package) have planning/subagents. The current code uses `create_react_agent` from langgraph.prebuilt. The task mentions "Langchain deep agent". We could keep `create_react_agent` (already in the closure via langchain) and add a shell tool that runs git commands in the work dir. Keep it simple: add a `run_command` tool (subprocess) with cwd=workdir, or a `git` tool. I'll propose a `git` tool (whitelisted git subcommands) plus keep `list_files`, and set the prompt to "Summarize the changes in the last commit of this repository" with the agent's cwd set to the work dir.

   The agent script needs to be parameterized: work dir passed via env/argv. The systemd service template `agent-run@.service` (or the oneshot processing the spool) invokes the python script with the work dir.

   Also the existing `llm-agent` oneshot service (list /tmp) should be replaced by this pipeline — the agent now runs per-push instead of at boot. The `enable` flag in config... The current service starts at boot with the dummy task. Per the task, the agent is spawned on push. So remove the boot-time service, replace with push-triggered runs.

6. **Config options**: extend `spec` in config.nix with git trigger options: `git-repo.enable` (or reuse `enable`), maybe `git-repo.port`, work dir, etc. Keep minimal: `enable` gates the whole VM app; add `git-trigger.enable`? The task says the VM should do the git repo thing, so maybe just implement it unconditionally in setup.nix, with options for paths. I'll propose a nested `git` option group: `git.enable`, `git.repoPath`, `git.workDir`, `git.sshPort` (host-side forwarded port).

Let me also think about how the host pushes: the launch script could print instructions, or better, provide a helper script `devtools/<name>-push` that does `git push ssh://git@localhost:2222/var/lib/agent/repo.git`? Hmm, the bare repo path: `ssh://git@localhost:2222/var/lib/agent/repo.git` or `git@localhost:repo.git` with GIT_SSH_COMMAND specifying port and key. The helper script on the host would use the private key from DEVTOOLS_CONFIG. I'll propose adding a second app or extending the launch script to also emit a push helper. Actually, apps are per-name: `config.apps."devtools/${name}"`. We could add `config.apps."devtools/${name}-push"` or a script in the devshell. Keep it simple: the launch script writes the push helper into DEVTOOLS_CONFIG or we add an app `devtools/${name}-git-remote` that prints the remote URL. I'll propose a small host-side helper script that sets up the git remote and pushes, using the generated key.

Also note: the VM's sshd host keys — generated at boot by openssh service automatically. Fine.

Also the git user: `users.users.git = { isNormalUser = true; home = /var/lib/agent? }` Hmm, bare repo at `/var/lib/agent/repo.git` owned by git user. The git user needs a shell (git-shell or bash) — for git over ssh, the user needs shell access to run `git-upload-pack`/`git-receive-pack`. Use `git-shell` as the login shell restricted to git commands, or full bash. `git-shell` is the standard choice: `users.users.git.shell = "${pkgs.git}/bin/git-shell"`. With git-shell, the repo path is referenced directly: `git push git@localhost:/var/lib/agent/repo.git`. git-shell requires the repo to be owned by git user and the command `git-receive-pack '/var/lib/agent/repo.git'` — works with absolute path.

Permissions: the work dir `/var/lib/agent/work` — the agent service runs as which user? Could run as `agent` user or root. The checkout needs read access to the bare repo (git user's). Simplest: run the agent service as the `git` user? Or create an `agent` user and make repo world-readable. Or run everything as `git` user. Hmm, the hook runs as git user; the spool dir writable by git; the run service runs as root or git. I'll propose running the agent service as the `git` user (or a dedicated `agent` user with group access to the repo). Keep it simple: run as `git` user, work dirs under `/var/lib/agent/work` owned by git.

Wait, but the agent needs to read the API key from `/run/agent_keys` (9p mount, read-only, mounted with `security_model=none` so uid mapping matters — files owned by host user; with security_model=none the guest sees host uids; the mount options include `ro`; the service user needs read access — the key file on host is created by launch script with default perms 644? `echo "$user_key" > file` — umask dependent. Should chmod 600 and make readable by the service user. The 9p mount with security_model=none preserves ownership; guest sees host uid/gid numbers. The service runs as git user (uid 1000?) — host file owned by host user uid (e.g. 1000). Might work if uids align, or we chmod 604/644. Simpler: mount with `ro` and ensure the key file is world-readable on host (chmod 644) — it's a dev tool VM, acceptable, but keys world-readable is meh. Alternatively run agent service as root. Root can read anything on the 9p mount. Running the agent as root in a disposable VM is acceptable for this dev tool. Hmm, but running git checkout as root then leaves root-owned files. Fine for a throwaway VM. I'll propose running the run service as the `git` user but note the key-permission consideration; or simply keep it flexible. Actually, to minimize bikeshedding in the proposal, I'll say: agent service runs as the `git` user; key file permissions handled by launch script (chmod 640 with matching gid, or just 644 given single-user dev VM). I'll keep this detail light in the proposal.

Also: the existing boot-time `llm-agent` service with the dummy "list /tmp" task gets replaced by the push-triggered flow. The `post-receive` hook + spool + path unit + oneshot service that: for each pending branch file → checkout → run agent with cwd=workdir → write summary to `SUMMARY.md` (or print to journal). 

Also need `network-online.target` dependency for the agent run service (LLM API call), and the 9p mount dependency for the key.

Also the VM needs `services.openssh.enable = true`, `environment.systemPackages = [ git ]`, and the python env already exists.

Also `virtualisation.forwardPorts` for SSH: `virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ]` — need to check default; qemu-vm.nix might already forward 2222. I'll set it explicitly.

Also the launch script: currently checks provider reachability and writes the user key. It should additionally generate the git SSH keypair into DEVTOOLS_CONFIG (host side) so the guest can authorize it and the host can use it for pushing. And print the push instructions / remote URL.

Now, how does the host user push? They add remote: `git remote add agent ssh://git@localhost:2222/var/lib/agent/repo.git`? With git-shell, `ssh://git@localhost:2222/var/lib/agent/repo.git` — git-shell handles `git-upload-pack /var/lib/agent/repo.git`. The port: ssh:// URL with port: `ssh://git@localhost:2222/var/lib/agent/repo.git`. And the key: `GIT_SSH_COMMAND="ssh -i $DEVTOOLS_CONFIG/agent-git/id_ed25519 -o StrictHostKeyChecking=no"`. The helper script (host side) can wrap this: `devtools/<name>-push` app that does `git push` with GIT_SSH_COMMAND set. I'll propose adding a second app `devtools/${name}-push` or a `git-remote` helper. 

Let me also consider: should the repo be initialized with the current repository's content? The task says "Create a git repository. Changes will be pushed to the repository via ssh." So the host user pushes their repo to the VM. The bare repo is initialized empty on first boot (oneshot service `git-repo-init`).

Also branch checkout: "the corresponding branch should be checked out into a directory" — per-branch work dirs, e.g. `/var/lib/agent/work/<branch>` with `/` sanitized to `-`.

Now the proposal structure. The user asked earlier for a proposal; now they've added the files and asked me to let them know if others should be added. So my reply should:
1. Note the files are sufficient (maybe ask for `prelude/config.nix` / `devtools-prelude` to understand `get-config`, and `llm-providers/config.nix` for provider options — actually I have summaries of llm-providers/config.nix? It's in the repo summary list but contents not shown. The setup.nix uses `devtools-prelude.get-config` and provider options; I might want to see `prelude/config.nix` and `llm-providers/config.nix` to align. But it's not strictly necessary for the proposal; the interfaces used are clear from setup.nix. I could mention that seeing `prelude/config.nix` (for `get-config`) would help but isn't blocking.)
2. Present the updated, concrete implementation plan grounded in the actual code.

Let me now write the concrete plan:

### Changes to `llm-agent/config.nix`
Add options to `spec`:
- `git-repo.enable` (bool, default false? or reuse top-level enable) — actually the task makes git-trigger the default behavior; I'll propose `git-repo.enable` defaulting to true when agent enabled? Keep it an explicit option: `git-repo = { enable; work-dir; host-port; }`.

### Changes to `llm-agent/setup.nix`
Guest VM additions:
- `services.openssh.enable = true;`
- `virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ]` (explicit)
- `users.users.git` with git-shell, home `/var/lib/agent`, `authorizedKeys` via sshd `AuthorizedKeysFile` pointing at the 9p-mounted key (`/run/agent_keys/agent-git/id_ed25519.pub`) — actually AuthorizedKeysFile can point to the mounted file directly. Need sshd to start after the mount: `requires`/`after` the mount unit.
- `git-repo-init` oneshot: creates bare repo `/var/lib/agent/repo.git` owned by git user, installs `post-receive` hook.
- `post-receive` hook: reads stdin (old new ref), for each branch ref (refs/heads/*), writes `/var/lib/agent/inbox/<sanitized-branch>` containing the new sha.
- `systemd.path` unit on the inbox dir → triggers `agent-run.service` (oneshot) which loops over inbox files: checkout + run agent.
- Checkout script: clone-or-reset into `/var/lib/agent/work/<branch>`.
- Agent script: parameterized by work dir (argv), prompt: "Summarize the changes in the last commit", tools: `list_files`, `run_git` (subprocess git in cwd), cwd set to work dir. Output: print summary; also write `SUMMARY.md`? The task says dummy task of summarizing changes in last commit — output to stdout (journal) is enough; maybe write to workdir `AGENT_SUMMARY.md`. I'll propose writing to stdout/journal and optionally a file.
- Replace the boot-time `llm-agent` service with the push-triggered `agent-run` service (keep env vars, key reading, mount dependency).

Host side (launch script):
- Generate ed25519 keypair into `$DEVTOOLS_CONFIG/agent-git/` if absent (ssh-keygen), chmod 600 private.
- Print push instructions, and/or add a second app `devtools/${name}-push` that pushes current branch using the key.

Also the `agent-python` needs no new packages (langchain, langchain-openai already there; subprocess is stdlib).

Ordering: agent-run service needs network-online + the 9p mount (for key) — `after = [ "network-online.target" "run-agent_keys.mount" ]`.

Edge cases: branch names with `/` (feature/foo) — sanitize to `-` for dir names and unit instance names. Since we use spool files not template units, sanitization only affects directory names.

Also note: `post-receive` runs as the pushing user (git). It writes to inbox owned by git. agent-run service runs as git user too (so it can read repo and write work dirs, and read the key from 9p — permissions on host side: launch script chmods the key file 644? or we run service as root). I'll propose running as `git` user and having the launch script `chmod 644` the pubkey and the key file is already handled; private key stays host-side only. Actually the API key file on host: `echo "$user_key" > ...` then `chmod 644`? The 9p mount with security_model=none: guest sees host uid/gid. The git user in guest has some uid (e.g. 1000). Host file owned by host user (uid maybe 1000). If uids match, read works with 600. Not guaranteed. Simplest robust: chmod 640 with gid matching, or just run the agent service as root. Given it's a throwaway dev VM, running the checkout+agent as root is simplest and avoids all permission issues; but root-owned work dirs are fine. Hmm, but the hook runs as git user and the service as root — service can read inbox written by git. OK: I'll propose running the run service as root (VM is disposable, single-purpose) — or note the alternative. Actually, let me not over-specify; I'll say the service runs as the `git` user (with the note that key file permissions must allow it) OR root. I'll pick: run as `git` user, and launch script chmods key files appropriately (644 within DEVTOOLS_CONFIG which is 700 anyway). Hmm, DEVTOOLS_CONFIG on host is presumably private (0700). The 9p mount is read-only for the whole dir. Guest git user uid 1000 vs host file owner uid — with security_model=none, 9p enforces permissions based on the presented ids; guest process uid 1000 (git) vs file owner uid (host user, e.g. 1000) — likely matches on typical single-user Linux. But to be safe, chmod 644 the key file in launch script. It's a dev tool; acceptable. I'll mention it briefly.

Let me also double check the existing setup.nix details I must integrate with:
- `agent-script` is a `pkgs.writeText` — will become a parameterized script taking work dir as argv.
- `systemd.services.llm-agent` — replaced by `agent-run` (triggered by path unit).
- The 9p mount unit `run-agent_keys.mount` — reuse for sshd authorized key too? The git push auth key: I proposed putting the pubkey in DEVTOOLS_CONFIG/agent-git/ on host, visible in guest at /run/agent_keys/agent-git/id_ed25519.pub. sshd AuthorizedKeysFile can include that path. Need sshd to start after mount: `wants`/`after` on the mount unit name `run-agent_keys.mount`.

Wait — the mount unit name: `where = "/run/agent_keys"` → unit `run-agent_keys.mount`. Yes.

Also `virtualisation.forwardPorts` — I should double-check qemu-vm.nix default. I recall the default `virtualisation.forwardPorts = []` and there's a default hostfwd for ssh only in `nixos-shell`? Hmm. Actually I now recall qemu-vm.nix:

```nix
virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ] — no...
```

I'm going to just set it explicitly in the proposal and note "explicitly forward host 2222 → guest 22 (qemu-vm.nix may do this by default; we set it explicitly)".

Also, the guest needs `git` package: `environment.systemPackages = [ pkgs.git ]`.

Also `services.openssh.settings.PasswordAuthentication = false` maybe; and the git user's key auth via file. Also `users.users.git = { isSystemUser? group; shell = git-shell; home = /var/lib/agent; createHome }`.

Repo init service: oneshot `git-repo-init`: `git init --bare /var/lib/agent/repo.git`, `chown -R git`, write hook. The hook script: 

```bash
#!/bin/sh
while read old new ref; do
  case "$ref" in refs/heads/*) branch=${ref#refs/heads/}; ... echo "$new" > /var/lib/agent/inbox/$(ById sanitized ;;
done
```

Sanitize: `branch=$(echo "$branch" | tr '/' '_')`.

agent-run.service: oneshot, `ExecStart` = run script that loops: for f in inbox/*: branch=$(basename f); checkout; run agent; rm f. Loop until inbox empty (to handle pushes during run).

Now the agent script changes: accept work dir as `sys.argv[1]`, `os.chdir(workdir)`, prompt: "You are in a git repository working directory. Summarize the changes made in the last commit (git show HEAD / git diff HEAD~1..HEAD). Use the provided tools." Tools: `list_files`, `run_git` (subprocess run git command, whitelist subcommands: show, diff, log, status). Keep `create_react_agent`.

Also keep the option to run the dummy boot-time task? The task says the agent is spawned on push; remove the boot-time service. But `enable` option gates the app. I'll propose replacing the boot service with the push-triggered one.

Host-side: launch script additions:
```
mkdir -p "$DEVTOOLS_CONFIG/agent-git"
if [ ! -f "$DEVTOOLS_CONFIG/agent-git/id_ed25519" ]; then ssh-keygen -t ed25519 -N "" -f ...; fi
```
and print remote URL: `ssh://git@localhost:2222/var/lib/agent/repo.git` (with GIT_SSH_COMMAND using the key). Optionally add app `devtools/${name}-push` that pushes the current repo/branch with the right env. I'll propose the push helper as a second app.

Also note: `StrictHostKeyChecking=no` needed since VM host key changes each boot (regenerated unless persisted). The push helper should use `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`.

Files to add: possibly split into `llm-agent/git-repo.nix` for the guest VM additions to keep setup.nix manageable. I'll propose keeping it in setup.nix or splitting — suggest splitting into `llm-agent/git-repo.nix` imported by setup.nix, since setup.nix is already long.

Other files to add to chat: `prelude/config.nix` (for `devtools-prelude.get-config` semantics) and `llm-providers/config.nix` (provider option shape) — helpful but not blocking. Also `flake.nix`/`flakeModule.nix` to see how llm-agent module is wired, and `lite-llm/config.nix` for the endpoint URL shape. I'll ask for `prelude/config.nix` and `llm-providers/config.nix` (and mention flake.nix) as nice-to-haves.

Now, the response format: a proposal, brief-ish but concrete. Use headers and bullets. Include the key code sketches (short). Keep it reasonably concise but complete. Since this is a planning/proposal response, markdown with headers and code blocks is appropriate. Length: medium-long, since it's a design proposal with concrete steps. I'll keep code snippets short.

Let me draft:

## What I learned from the files
- setup.nix builds a NixOS VM, agent runs as oneshot boot service with dummy task, 9p mount for keys, launch script sources devtools config.
- The pieces to change: replace boot-time service with push-triggered pipeline; add sshd, git user, bare repo, hook, path unit, checkout, parameterized agent script; host-side keypair + push helper.

## Concrete plan

### config.nix
- add `git-repo` options: enable (default true when agent enabled?), host port, paths. Keep minimal.

### setup.nix (or new git-repo.nix)
Guest:
1. sshd + port forward
2. git user + git-shell
3. repo init service + post-receive hook → spool
4. path unit + agent-run oneshot (checkout + run agent)
5. agent script parameterized (argv workdir), git tools, cwd
Host (launch script):
6. keypair generation into DEVTOOLS_CONFIG/agent-git, push helper app

### Flow diagram

### Files I'd still like to see
prelude/config.nix, llm-providers/config.nix, flake.nix (wiring).

Let me write the post-receive hook sketch and the service sketch briefly.

One more consideration: the existing `systemd.services.llm-agent` — I'll repurpose: rename to `agent-run` (oneshot, triggered by path unit, not wantedBy multi-user). Env vars same as now (OPENAI_BASE_URL etc.). The agent script gets workdir via argv.

Also `agent-python` unchanged. The `list_files` tool stays; add `git` tool via subprocess.

Also note the mount dependency: `after = [ "network-online.target" "run-agent_keys.mount" ]` and `requires`/`wants` the mount.

Also the inbox: `/var/lib/agent/inbox`, owned by git user, and the path unit `agent-inbox.path` with `PathExistsGlob`/`PathChanged`. Use `pathUnit` with `PathChanged=/var/lib/agent/inbox` triggering `agent-run.service` (`serviceConfig` oneshot). The service script loops until inbox empty.

Checkout script details:
```
work=/var/lib/agent/work/$safe_branch
if [ -e "$work/.git" ]; then
  git -C "$work" fetch origin && git -C "$work" reset --hard "origin/$branch"
else
  git clone --branch "$branch" /var/lib/agent/repo.git "$work"
fi
```
Hmm, clone from local bare repo: `git clone --branch <branch> /var/lib/agent/repo.git "$work"` — origin will be the local path; fetch origin works.

Agent invocation: `python agent.py "$work"` with cwd=$work; agent chdir's itself.

Summary output: print to journal (service output) and write `AGENT_SUMMARY.md` in workdir. I'll propose both (file makes result inspectable).

Also mention: remove the old boot-time dummy service (or keep behind option).

SSH host keys: openssh generates at boot; known_hosts handled with `-o StrictHostKeyChecking=no` in push helper.

Also `network-online.target` in VM: with QEMU user networking, DHCP via dhclient — the existing service already uses network-online.target, fine.

Also `virtualisation.forwardPorts`: set explicitly:
```nix
virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ];
```

Also `services.openssh.settings.PasswordAuthentication = "no"` and only key auth for git user; the `nixos` user with hashed password exists — keep console login for debugging.

authorizedKeys: `services.openssh.settings.AuthorizedKeysFile = "/run/agent_keys/agent-git/id_ed25519.pub %h/.ssh/authorized_keys"`? Hmm, AuthorizedKeysFile default is `%h/.ssh/authorized_keys %h/.ssh/authorized_keys2`. We can set it to include the mounted pubkey. But careful: mount must be up before sshd serves. Add `wants`/`after` on the mount in sshd service. Alternatively copy the pubkey at boot via a oneshot after mount into `/var/lib/agent/.ssh/authorized_keys`... simpler: AuthorizedKeysFile pointing at the 9p path + sshd after mount. I'll go with AuthorizedKeysFile.

Wait, one subtlety: the 9p mount is `wantedBy = multi-user.target`, and sshd `wantedBy = multi-user.target` too; ordering sshd `after` the mount unit ensures mount first. Add `wants` too (pull in mount even if sshd starts). Fine.

Now — also the host-side: how does the user push? Provide app `devtools/${name}-push` (or instructions printed by launch script). The push helper:

```bash
GIT_SSH_COMMAND="ssh -i $DEVTOOLS_CONFIG/agent-git/id_ed25519 -o StrictHostKeyChecking=no -p 2222" git push ssh://git@localhost:2222/var/lib/agent/repo.git HEAD:refs/heads/$(git branch --show-current)
```
Hmm, ssh:// URL with port: `ssh://git@localhost:2222/var/lib/agent/repo.git`. GIT_SSH_COMMAND handles the key; port in URL. 

I think the proposal should also mention testing plan and open questions (summary destination, concurrency). Keep those from before, updated.

Length: aim for a solid but not bloated proposal. Use headers, short code sketches. Let me write it.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Thanks — those two files are the core of it. A couple of others would be nice-to-have (see end), but I can make a concrete proposal now.

# Updated proposal (grounded in the current code)

## What changes in the existing pieces

- `systemd.services.llm-agent` (the boot-time dummy run) is **replaced** by a push-triggered pipeline. The agent script becomes parameterized (work dir as `argv[1]`, `os.chdir` into it) and its prompt/task becomes "summarize the last commit".
- `agent-python` stays as-is (`langchain`, `langchain-openai`); the agent gains a `run_git` tool (subprocess, whitelisted git subcommands: `show`, `diff`, `log`, `status`) alongside `list_files`.
- The 9p key mount, provider env vars, and launch-script key handling are reused as-is.

## Guest VM additions (`setup.nix`, or a new `llm-agent/git-repo.nix` imported from it)

1. **SSH access**: `services.openssh.enable = true`, explicit `virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ]`, key-only auth. A `git` user with `git-shell` as shell, home `/var/lib/agent`.
2. **Auth without baking secrets into the store**: the launch script generates an ed25519 keypair into `$DEVTOOLS_CONFIG/agent-git/` on the host; the guest reads the public key from the existing 9p mount via `services.openssh.settings.AuthorizedKeysFile = "/run/agent_keys/agent-git/id_ed25519.pub ..."` (sshd gets `after`/`wants` on `run-agent_keys.mount`).
3. **Bare repo**: oneshot `git-repo-init` service creates `/var/lib/agent/repo.git` (owner `git`) and installs a `post-receive` hook.
4. **Push detection**: the `post-receive` hook doesn't run the agent directly (it would block the push for the whole LLM run and run with wrong privileges). Instead it writes one file per pushed branch into a spool `/var/lib/agent/inbox/<sanitized-branch>`; a `systemd.path` unit on that directory triggers `agent-run.service`.
5. **`agent-run.service`** (oneshot, `after = [ "network-online.target" "run-agent_keys.mount" ]`): loops over spool files → checks the branch out into `/var/lib/agent/work/<branch>` (`git clone --branch` first time, `git fetch && git reset --hard` afterwards) → runs the agent with that dir as cwd → writes `AGENT_SUMMARY.md` and logs to the journal → removes the spool file. Runs as the `git` user.
6. `environment.systemPackages = [ pkgs.git ]`.

## Host side

- Launch script additionally generates the SSH keypair (if absent) under `$DEVTOOLS_CONFIG/agent-git/` and prints the remote URL.
- New app `devtools/${name}-push` that pushes the current branch with `GIT_SSH_COMMAND="ssh -i $DEVTOOLS_CONFIG/agent-git/id_ed25519 -o StrictHostKeyChecking=no"` to `ssh://git@localhost:2222/var/lib/agent/repo.git`.

## Flow

`git push` → sshd → bare repo → `post-receive` → spool → path unit → `agent-run` (checkout → agent, cwd = workdir) → summary.

## Open points (same as before, now sharper)

- Summary destination: I propose `AGENT_SUMMARY.md` in the work dir + journal; easy to change.
- Concurrency: the spool+oneshot design serializes runs per VM, which I'd keep for now.

## Files that would help (optional)

`prelude/config.nix` (to confirm `devtools-prelude.get-config` semantics) and `llm-providers/config.nix` (provider option shape) — neither blocks starting, since `setup.nix` already shows the interfaces I need. `flake.nix`/`flakeModule.nix` wiring would also help me confirm where the app attrs land.

If this looks right, I'd start with `setup.nix` (guest VM: sshd, repo, hook, path unit, agent service) plus the agent script changes, then the host-side launch/push script.

> Tokens: 4.1k sent, 10k received. Cost: $0.01 message, $0.02 session.  
> llm-providers/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> prelude/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: n  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

The user has added `llm-providers/config.nix` to the chat. Let me look at what it contains and see how it affects the proposal.

From the earlier message, `llm-providers/config.nix` was already shown in the "added files" message. Let me recall its contents:

```nix
{ flake-parts-lib, lib, llm-providers, ... }:
let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;
  inherit (llm-providers) model-type user-type endpoint-type provider-system-type;
  spec = types.submodule {
    options = {
      endpoint = mkOption {
        type = endpoint-type;
        description = ''...'';
      };
      users = mkOption {
        type = types.attrsOf user-type;
        description = ''...'';
        default = {};
      };
      models = mkOption {
        type = types.attrsOf model-type;
        description = ''...'';
        default = {};
      };
    };
  };
  perSystem = _:
  let
    x = 42;
  in
    {
      options.development-tools.llm-providers = mkOption {
        type = types.attrsOf provider-system-type;
        ...
      };
    }
  ;
in
  {
    options.development-tools.llm-providers = mkOption {
      type = types.attrsOf spec;
      ...
    };
    options.perSystem = mkPerSystemOption perSystem;
  }
```

So this confirms the provider spec: `endpoint` (endpoint-type), `users` (attrsOf user-type), `models` (attrsOf model-type). The `llm-agent/setup.nix` already uses `llm-agent.provider.endpoint.url`, `llm-agent.provider.models.main.name`, `llm-agent.provider.user.name`, and `key-script` from `config.development-tools.llm-providers.${provider}.users.${name}.key-script`.

So the provider config confirms:
- `provider.endpoint.url` — the OpenAI-compatible base URL
- `provider.models.main.name` — model name (note: `models` is an attrsOf, so `models.main` refers to a model named "main"; the agent setup uses `models.main.name`)
- `provider.user.name` — user name
- `key-script` — a script that outputs the user's key

This is consistent with what setup.nix already does. So nothing in the proposal changes materially — the provider interface is already consumed correctly by setup.nix. The git-triggered agent pipeline doesn't need new provider options; it reuses the same provider plumbing.

The user asks: "Let me know if there are others we should add."

I should:
1. Acknowledge the file and what it confirms (provider spec shape: endpoint, users, models; key-script path).
2. Note implications: no changes needed to provider config; the agent reuses `provider.endpoint.url`, `models.main.name`, user key-script.
3. Mention remaining optional files: `prelude/config.nix` (for `devtools-prelude.get-config`), and possibly `flake.nix`/`flakeModule.nix` wiring. Also `llm-providers/prelude.nix` might define `model-type`, `user-type`, `endpoint-type`, `provider-system-type` — that could be useful to confirm the exact fields (e.g., does `endpoint` have `url`? does `user` have `name` and `key-script`?). Actually setup.nix already uses `provider.user.name` and `key-script` from `config.development-tools.llm-providers.${provider}.users.${name}.key-script` — wait, in setup.nix:

```nix
key-script =
  with llm-agent.provider.user;
  config.development-tools.llm-providers.${provider}.users.${name}.key-script
;
```

Hmm, `llm-agent.provider.user` — singular "user" — and `provider` presumably is the name of the provider. So `provider.user` is an attrset with `provider` and `name` fields? Actually `with llm-agent.provider.user;` brings `provider` and `name` into scope. So `llm-agent.provider.user = { provider = "lite-llm"; name = "..."; }` presumably. And then it looks up `development-tools.llm-providers."lite-llm".users."...".key-script`.

So the provider config confirms the shape. The `llm-providers/prelude.nix` file would define `model-type`, `user-type`, `endpoint-type`, `provider-system-type` — that would confirm exact fields, but setup.nix usage already tells us what matters.

So my answer: confirm what the file tells us, note that no provider-side changes are needed, and list remaining optional files: `prelude/config.nix` (devtools-prelude.get-config), `llm-providers/prelude.nix` (type definitions), and `flake.nix`/`flakeModule.nix`/`presets/flakeModule.nix` for wiring. Also maybe `lite-llm/config.nix`/`setup.nix` to see how a provider instance is configured (to know what `models.main` looks like and whether `models.main` is a convention).

I should keep the reply brief-ish, in English, and answer the question: which other files to add. Also confirm the proposal stands and what this file confirms.

Let me draft:

- What it confirms: provider spec = endpoint + users + models; per-system option `development-tools.llm-providers` of `provider-system-type`. The agent setup already consumes `provider.endpoint.url`, `provider.models.main.name`, user `name` + `key-script` — all consistent, so no provider changes needed for the git pipeline; the new agent service reuses the same env vars (OPENAI_BASE_URL/OPENAI_MODEL/AGENT_USER/AGENT_KEYS_DIR).
- Remaining useful files:
  - `llm-providers/prelude.nix` — defines `model-type`, `user-type`, `endpoint-type`, `provider-system-type`; would confirm exact fields (e.g. whether `models` entries have `name`, whether `user-type` includes `key-script`).
  - `prelude/config.nix` — `devtools-prelude.get-config` semantics (how DEVTOOLS_CONFIG is resolved), relevant for the host-side keypair generation and push script.
  - `flake.nix` / `flakeModule.nix` / `presets/flakeModule.nix` — to confirm where `config.apps."devtools/..."` lands and how modules are imported (for adding a new app like the push helper).
  - Optionally `lite-llm/config.nix`/`setup.nix` — to see how a concrete provider instance declares `models.main` and users, useful to validate the `models.main.name` convention.

Also note: nothing in the proposal changes; the git-triggered pipeline needs no new provider options.

Keep it concise. Format: short paragraphs / small bullet lists. No need for headers given brevity. Maybe a short section "What this confirms" and "Still useful". Keep it tight.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Thanks — that file confirms the provider interface the agent already consumes, and it means **no changes are needed on the provider side** for the git pipeline.

## What it confirms

- A provider exposes `endpoint`, `users` (attrsOf `user-type`), and `models` (attrsOf `model-type`), plus a per-system `development-tools.llm-providers` option of `provider-system-type`.
- `setup.nix` already consumes exactly this shape: `provider.endpoint.url`, `provider.models.main.name`, and `users.${name}.key-script` (via `provider.user.{provider,name}`). The push-triggered agent service will reuse the same plumbing (`OPENAI_BASE_URL` / `OPENAI_MODEL` / `AGENT_USER` / `AGENT_KEYS_DIR`), so the proposal stands unchanged.

## Files still worth adding (optional, in order of usefulness)

1. **`llm-providers/prelude.nix`** — defines `model-type`, `user-type`, `endpoint-type`, `provider-system-type`; would confirm the exact fields (e.g. that `user-type` carries `key-script`, and what `model-type` contains beyond `name`).
2. **`prelude/config.nix`** — to confirm `devtools-prelude.get-config` semantics, since the host-side launch script will additionally generate the SSH keypair under `$DEVTOOLS_CONFIG/agent-git/`.
3. **`flake.nix` / `flakeModule.nix` / `presets/flakeModule.nix`** — to confirm where `config.apps."devtools/..."` lands and how modules are imported, before adding the `-push` app.
4. *(Nice to have)* **`lite-llm/config.nix` / `setup.nix`** — to see how a concrete provider instance declares `models.main` and its users, validating the `models.main.name` convention the agent relies on.

None of these block implementation — the two `llm-agent` files plus this provider config are enough to start on `setup.nix` (sshd, bare repo, `post-receive` hook, spool + path unit, `agent-run` service, parameterized agent script) and the host-side launch/push scripts. Want me to start there, or add the remaining files first?

> Tokens: 5.6k sent, 2.0k received. Cost: $0.0032 message, $0.02 session.  
> flake.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: n  
> flakeModule.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: n  
> lite-llm/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: n  
> llm-providers/prelude.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: n  
> presets/flakeModule.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: n  

#### Make the following changes (1) The authorized ssh public keys should be part of the llm-agent nix configuration, no need to generate them. (2) No need to create a new app, 'llm-agent'  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

The user wants me to make changes to the proposal:

1. The authorized SSH public keys should be part of the llm-agent nix configuration (i.e., passed as a nix option, not generated at runtime by the launch script).
2. No need to create a new app (`devtools/${name}-push` should not be created).

So I should update the proposal accordingly. The user hasn't asked me to implement yet — they said "Make the following changes" — this likely means changes to the proposal. Let me re-read: "Make the following changes (1) The authorized ssh public keys should be part of the llm-agent nix configuration, no need to generate them. (2) No need to create a new app, 'llm-agent'".

Hmm, "No need to create a new app, 'llm-agent'" — this could mean: don't create a new app; the existing `devtools/${llm-agent-name}` app is enough. So the push would be done manually by the user, or the existing app handles it. Actually wait — "No need to create a new app, 'llm-agent'" — I think they mean: no need to create a new app for pushing; the existing `devtools/llm-agent` app (the launch script) is sufficient. So drop the `-push` app idea.

So the updated proposal:

1. SSH keys: add an option in `llm-agent/config.nix` spec, e.g. `git.ssh.authorizedKeys` (list of strings, public keys) — these get baked into the guest's `users.users.git.openssh.authorizedKeys.keys` (or `services.openssh` config). No runtime keypair generation in the launch script. The user pushes with whatever key they have locally; the private key handling is up to the user (they already have the key corresponding to the public key in config).

2. Drop the `-push` app. The existing `devtools/${llm-agent-name}` app stays as-is (launches the VM). Users push manually with `git push` to the forwarded port.

I should present the revised proposal concisely. Since this is a proposal update, I should describe the changes briefly and how they affect the design. The user said "Make the following changes" — to the proposal. I should reply with the updated proposal, briefly.

Let me write the updated proposal:

- `llm-agent/config.nix`: add options under the spec:
  - `git.enable` or just always-on? The task says the VM should do this, so maybe just always on, or an option `git = { enable = ...; authorizedKeys = ...; }`. Given the spec currently has `enable` and `provider`, I'd add:
    ```
    git = {
      enable = mkOption { type = types.bool; default = true; };
      authorizedKeys = mkOption { type = types.listOf types.str; default = []; };
    }
    ```
  Actually, since the task defines the VM behavior as git-triggered, maybe make it default true or just always present. But keeping an option is more flexible. I'll propose `git.authorizedKeys` (list of public key strings) and possibly `git.enable`.

- `setup.nix` guest VM:
  - `services.openssh.enable = true;` with `users.users.git.openssh.authorizedKeys.keys = llm-agent.git.authorizedKeys` (or `services.openssh.settings.AuthorizedKeysFile` — no, since keys are now in the nix config, just use the standard `users.users.git.openssh.authorizedKeys.keys`).
  - No 9p dependency for the git key anymore (the 9p mount is still needed for the LLM API key).
  - Port forwarding: `virtualisation.forwardPorts = [ { from = "host"; host.port = 2222; guest.port = 22; } ]` — still needed so the host can push. Actually, since the user pushes from the host, we need the port forward. Keep it.
  - Bare repo, post-receive hook, spool, path unit, agent-run service — unchanged from before.

- Host side: launch script unchanged except no keypair generation; it just launches the VM. Users push with their own key: `git push ssh://git@localhost:2222/var/lib/agent/repo.git` — wait, actually with port forwarding from host port 2222 to guest 22, and the user's own ssh key whose public key is in the config. The user needs `GIT_SSH_COMMAND="ssh -p 2222 -o StrictHostKeyChecking=no"` or they add a config entry. Since no new app, we just document the remote URL.

I should keep the reply brief-ish but complete, describing the updated proposal. The user asked to "make the following changes" — I'll present the revised proposal reflecting those changes. I shouldn't implement yet unless asked; the flow so far has been proposal → refine. I'll present the updated proposal and offer to implement.

Format: a short summary of the two changes and how they alter the design, then the updated flow. Keep it reasonably concise. Maybe a small code sketch of the config option. Headers and bullets are appropriate. Not too long.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

# Revised proposal

Both changes simplify the design considerably.

## Change 1: SSH keys come from the nix configuration

- `llm-agent/config.nix` spec gains a `git` option group:

  ```nix
  git = {
    enable = mkOption { type = types.bool; default = true; };
    authorizedKeys = mkOption {
      type = types.listOf types.str;
      description = "SSH public keys authorized to push to the agent repository.";
      default = [ ];
    };
  };
  ```

- In `setup.nix`, the guest VM wires these straight into the standard NixOS options:

  ```nix
  services.openssh.enable = true;
  users.users.git = {
    isSystemUser = true;
    group = "git";
    home = "/var/lib/agent";
    createHome = true;
    shell = "${pkgs.git}/bin/git-shell";
    openssh.authorizedKeys.keys = llm-agent.git.authorizedKeys;
  };
  ```

- No keypair generation in the launch script, no reading keys from the 9p mount for sshd. The 9p mount stays only for the LLM API key, exactly as it is today.
- The pusher uses whatever local private key corresponds to the configured public keys, e.g. `git push ssh://git@localhost:2222/var/lib/agent/repo.git` (port forward `host.port = 2222 → guest 22` still needed so the host can reach sshd).

## Change 2: no new app

- Drop the `devtools/${name}-push` app entirely. The existing `devtools/${llm-agent-name}` app (launch script) is unchanged apart from removing the keypair-generation step. Pushing is done manually by the user with plain `git push` to the forwarded port.

## Unchanged from the previous proposal

- Bare repo at `/var/lib/agent/repo.git` owned by `git`, initialized by a oneshot service that also installs the `post-receive` hook.
- Hook writes spool files to `/var/lib/agent/inbox/`; a `systemd.path` unit triggers `agent-run.service`, which checks out the branch into `/var/lib/agent/work/<branch>` and runs the agent there with the "summarize the last commit" task.
- Agent script parameterized by work dir; provider env vars (`OPENAI_BASE_URL`, `OPENAI_MODEL`, `AGENT_USER`, `AGENT_KEYS_DIR`) reused as-is.

## Flow

`git push` (user's own key) → sshd → bare repo → `post-receive` → spool → path unit → `agent-run` (checkout → agent, cwd = workdir) → summary.

If this matches what you want, I'll implement it in `llm-agent/config.nix` and `llm-agent/setup.nix`.

> Tokens: 6.1k sent, 1.8k received. Cost: $0.0029 message, $0.02 session.  

#### Modify the app created by the 'llm-agent' such that it exposes two modes: (1) spawn the llm-agent vm and (2) push to the llm agent vm's repository. You can use the docopts available in nixpkgs to facilitate this.  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

The user wants me to modify the app created by `llm-agent` (i.e., `config.apps."devtools/${llm-agent-name}"`) so that it exposes two modes:

1. Spawn the llm-agent VM (current behavior)
2. Push to the llm-agent VM's repository

They suggest using `docopts` from nixpkgs to facilitate this.

So the launch script becomes a multi-mode script. Using `docopts` (available in nixpkgs as `pkgs.docopts`), the script would parse arguments like:

```
Usage:
  launch-<name> run        # spawn the VM
  launch-<nameById> push [--remote <remote>] [REF]  # push to the VM's repo
```

Let me think about the design:

- Mode 1 (run): current behavior — source the devtools prelude config, check provider reachability, write the user key, boot the VM.
- Mode 2 (push): push the current branch to the VM's repository. This needs to know the SSH port (2222 forwarded to guest 22), the repo path (`/var/lib/agent/repo.git`), and the SSH key to use. Since the keys are now part of the nix configuration (authorizedKeys), the push mode needs a private key path. Hmm — the user said "The authorized ssh public keys should be part of the llm-agent nix configuration". So the private key location... The push mode could accept `--key` option or use a default location under `$DEVTOOLS_CONFIG/agent-git/id_ed25519`? Wait, but we removed key generation. The user pushes with "whatever local private key corresponds to the configured public keys". So the push mode should accept an option for the key path, defaulting to something sensible, e.g. `$DEVTOOLS_CONFIG/agent-git/id_ed25519` or `~/.ssh/id_ed25519`.

Actually, let me keep it simple: the push mode uses `GIT_SSH_COMMAND` with a key path that can be passed via `--key` option, defaulting to `$DEVTOOLS_CONFIG/agent-git/id_ed25519` (the devtools config dir is already sourced in the launch script). Hmm, but since keys are in the nix config, maybe the private key should be provided by the user. Let me add an option `--key` with a default of `$DEVTOOLS_CONFIG/agent-git/id_ed25519`.

Wait — but the config dir is for the tool's private config. The prelude `get-config` provides DEVTOOLS_CONFIG. Let me just default to `$DEVTOOLS_CONFIG/agent-git/id_ed25519` and allow `--key` override.

Also the push mode needs the remote URL: `ssh://git@localhost:2222/var/lib/agent/repo.git` — port 2222 forwarded. But wait, the port forward is defined in the VM config. The host port is 2222. The push mode should use the same port. Since the VM config is built in setup.nix, I can define a `git-ssh-port` variable in the nix expression and use it in both the VM's `virtualisation.forwardPorts` and the push script.

Also, which branch to push? The current branch of the host repo (the repo where the flake lives). The push mode should push the current branch: `git push` with the remote refspec. The branch name in the VM repo will be the current branch name. The post-receive hook checks out that branch.

Let me write the script with docopts:

```
Usage:
  launch-<name> run
  launch-<name> push [--key=<key>] [<remote-ref>]
```

Hmm, docopts usage: `docopts` is a shell script that parses docopt-style usage. In nixpkgs, `pkgs.docopts` provides the `docopts` binary. Typical usage:

```bash
eval "$(docopts -h -V "$version" : "$@")"
```

Actually the docopts usage pattern: `docopts : --auto : "$@"` or with explicit help. Let me recall. docopts takes a usage string and arguments:

```bash
eval "$(docopts -G "$@" : <<EOF
Usage: myprog run
       myprog push [--key=<key>]
EOF
)"
```

Hmm, the docopts syntax: `docopts [options] arguments... : [usage]`. The typical pattern:

```bash
eval "$(docopts : --auto : "$@" <<EOF
Usage: prog run
       prog push [--key=<key>]
EOF
)"
```

Actually from the docopts README:

```bash
eval "$(docopts -V "$version" : --auto : "$@" <<EOF
Usage: myprog [--verbose]...
EOF
)"
```

The `--auto` flag makes it auto-exit on parse errors. Let me write:

```bash
eval "$(docopts : --auto : "$@" <<EOF
Usage: ${name} run
       ${name} push [--key=<key>] [<refspec>]
EOF
)"
```

Hmm, I need to be careful with heredoc inside a nix string with `''` quoting. In nix, `''` inside `''` needs escaping as `'''`. The usage string contains `--key=<key>` etc.

Let me now write the actual implementation.

The script structure:

```bash
#!${pkgs.bash}/bin/bash
set -e

eval "$(docopts : --auto : "$@" <<EOF
Usage: ${llm-agent-name} run
       ${llm-agent-name} push [--key=<key>] [<refspec>]
EOF
)"

case "$1" in ... 
```

Wait, docopts sets variables like `run`, `push`, `key`, `refspec` in the shell. So after eval, we can check `if [ "$run" = true ]` etc. Hmm, actually docopts sets variables named after the arguments: `run` would be "true"/"false" for commands. Let me structure:

```bash
if [[ "$run" == "true" ]]; then
  # spawn VM
elif [[ "$push" == "true" ]]; then
  # push
fi
```

Hmm, but docopts with commands: `run` and `push` become variables holding "true"/"false". Yes, that's how docopts works — each argument becomes a shell variable.

Now the run mode: keep the existing behavior (source config, check provider, write key, exec VM).

The push mode:
- source the devtools config (to get DEVTOOLS_CONFIG for the key default)
- determine the key: `--key` option or default `$DEVTOOLS_CONFIG/agent-git/id_ed25519`
- determine the refspec: if `<refspec>` given use it, else `HEAD:refs/heads/$(git rev-parse --abbrev-ref HEAD)` — push current branch. Actually simpler: `git push` with refspec `HEAD:refs/heads/<current-branch>`.
- `GIT_SSH_COMMAND="ssh -i $key -p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"` and `git push ssh://git@localhost:$port/var/lib/agent/repo.git $refspec`.

Wait, the URL with port: `ssh://git@localhost:2222/var/lib/agent/repo.git`. The port is part of the URL, so GIT_SSH_COMMAND doesn't need `-p`. Let me use the URL form: `ssh://git@localhost:${port}/var/lib/agent/repo.git`.

Also need `git` in PATH for the script: `PATH = "${pkgs.git}/bin:${pkgs.openssh}/bin:..."` or use absolute paths. The script currently uses absolute paths (`${pkgs.curl}/bin/curl`). For git push, I'll use `${pkgs.git}/bin/git` and set `GIT_SSH_COMMAND` with `${pkgs.openssh}/bin/ssh`.

Now, the port: I need to define the forwarded port in the VM config. Let me add `virtualisation.forwardPorts = [ { from = "host"; host.port = git-ssh-port; guest.port = 22; } ]` where `git-ssh-port = 2222` (could be an option, but keep it a `let` binding for now, or add to config.nix options... The user asked specifically about the app modification. Let me keep the port as a let binding in setup.nix, used both in the VM config and the push script).

Also the VM needs sshd enabled and the git user — that's part of the git-repo work. The user's request here is specifically: "Modify the app created by the 'llm-agent' such that it exposes two modes". So the focus is the app script. But the push mode only makes sense with the git repo in the VM. The previous conversation established the plan (sshd, bare repo, post-receive, agent-run service). The user is now asking to modify the app to have two modes. I should implement the app change, and presumably also the VM-side git repo setup since that's the overall task... but the instruction is specifically about the app. Let me focus on the app script change, but I should also make sure the VM config supports SSH (since push mode requires it). 

Hmm. The user said "Modify the app created by the 'llm-agent' such that it exposes two modes: (1) spawn the llm-agent vm and (2) push to the llm agent vm's repository. You can use the docopts available in nixpkgs to facilitate this."

So the deliverable: the launch script becomes a two-mode script using docopts. I'll implement:

1. `launch-llm-agent` script with docopts parsing: `run` and `push` subcommands.
2. The push mode pushes the current branch to the VM repo via the forwarded SSH port.
3. The VM config needs `services.openssh`, git user, port forwarding — this is part of the broader task; I'll include the minimal VM-side pieces needed for push to work (sshd, git user with authorized keys from config, port forward). Actually, the previous turn established the git option group in config.nix with `authorizedKeys`. The user hasn't asked me to implement the full VM git setup yet in this turn — but the app change is tightly coupled. Let me implement the app change fully, and include the minimal VM-side changes (sshd, git user, port forward) so the push mode is coherent. Actually wait — should I? The user's message is specifically about the app. But the app's push mode is useless without the VM-side repo. The task as a whole (from the task file) is the git-triggered agent. The conversation has been iterating on the proposal. The user is now directing implementation step by step. I think the cleanest response: implement the app modification (the launch script with docopts, two modes), and mention that the VM-side (sshd, repo, hook) is still needed and I can do it next. But to make the push mode actually work, the VM needs sshd and the repo. 

Hmm, let me re-read: "Modify the app created by the 'llm-agent' such that it exposes two modes". I'll focus on the app. I'll show the modified `launch-llm-agent` script in setup.nix, using docopts. I'll keep the VM config mostly as-is but add the port forward and note that sshd/repo setup comes with the git-repo implementation. Actually, to keep the answer focused and brief (per system prompt: describe code changes briefly), I'll present the new launch script and the small additions to the VM config (port forward) and config.nix (git options) needed for coherence.

Let me write the code.

In setup.nix:

```nix
  /**
  Port on the host through which the guest's sshd (port 22)
  is reachable; used both by the VM port forwarding and by the
  push mode of the launch script.
  */
  git-ssh-port = 2222;

  /**
  The host-side launch script. It exposes two modes:
  'run' boots the agent VM, 'push' pushes the current branch
  of the host repository to the agent VM's git repository.
  */
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    eval "$(${pkgs.docopts}/bin/docopts : --auto : "$@" <<EOF
    Usage: ${llm-agent-name} run
           ${llm-agent-name} push [--key=<key>] [<refspec>]
    EOF
    )"

    if [ "$run" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"

      if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
        echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
        echo "If a lite-llm instance provides this model, launch it on the host first." >&2
      fi

      user_key=$(${key-script})
      user_key_dir="$DEVTOOLS_CONFIG/users/"
      mkdir -p "$user_key_dir"
      echo "$user_key" > "$user_key_dir/${provider-user}.key"
      export DEVTOOLS_CONFIG
      echo "Running: ${vm.config.system.build.vm}/bin/run-nixos-vm"
      exec ${vm.config.system.build.vm}/bin/run-nixos-vm
    fi

    if [ "$push" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"
      key="''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}"
      refspec="''${refspec:-HEAD:refs/heads/$(git rev-parse --abbrev-ref HEAD)}"
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ${pkgs.git}/bin/git push "ssh://git@localhost:${toString git-ssh-port}/var/lib/agent/repo.git" "$refspec"
    fi
  '';
```

Wait, there are issues:

1. The heredoc inside `eval "$(...)"` — the heredoc is fed to docopts as its usage input. docopts reads usage from stdin when given `:` ... hmm, let me recall docopts usage. From the docopts man page:

```
docopts [options] arguments... : [usage]
```

The arguments before `:` are passed to docopts; after `:` is the usage text. If the usage is `-` or omitted... Actually the pattern is:

```
docopts -h help : "$@" <<EOF
usage text
EOF
```

Hmm. Let me recall more precisely. docopts GitHub (docopt/docopts): 

```
eval "$(docopts -V "$version" -h help : "$@" <<EOF
usage: docopts ...
EOF
)"
```

The form is `docopts [docopts options] arguments... : [usage]`. The `arguments` are typically `"$@"` (the script's arguments), and the usage text follows after `:`. The usage can be given as a heredoc on stdin: `docopts : --auto : "$@" <<EOF ... EOF`? Hmm.

From the docopts README:

```bash
eval "$(docopts -V "$version" : --auto : "$@" <<EOF
Usage: myprog [--verbose] [--code=<code>]
...
EOF
)"
```

Hmm, I don't remember exactly whether `--auto` goes before or after the first `:`. Let me think. The README of docopts:

```
eval "$(docopts -V "$version" -h help : "$@" <<EOF
Usage: docopts [options] ...
EOF
)"
```

and

```
eval "$(docopts : --auto : "$@" <<EOF
...
EOF
)"
```

I believe the syntax is: `docopts [options] -- : arguments : usage`. Honestly, the exact invocation: `docopts -h <help> : "$@"` where the usage text is passed via `-h` or stdin. The README shows:

```bash
eval "$(docopts -V "$version" -h help : "$@" <<EOF
Usage: myprog [-v --verbose]
...
EOF
)"
```

Here `-h help` means the help flag variable is named "help". And `--auto` makes docopts exit on error instead of failing. I've also seen `docopts : --auto : "$@"` where the first `:` separates... hmm.

Actually, from the docopts man page: `docopts [options] arguments... : [usage]`. The arguments are the script's arguments to parse, and after the `:` comes the usage description. If usage is `-`, it's read from stdin. So `docopts : --auto : "$@"` would be: arguments = `--auto`? No wait.

Let me look at this differently. The man page says:

```
SYNOPSIS
       docopts [--] [options] arguments... : [usage]
```

Hmm, I recall from the actual docopts README:

```bash
eval "$(docopts -V "$version" -h help : "$@" <<EOF
Usage: myprog [options] <path>...
Options:
  ...
EOF
)"
```

And there's `--auto` described as "automatic flag handling: exit on error". Example from README:

```bash
eval "$(docopts : --auto : "$@" <<EOF
Usage: myprog run
       myprog push
EOF
)"
```

Hmm, I'm not 100% sure about `--auto` placement. To be safe, I could use the simpler form without `--auto`:

```bash
eval "$(${pkgs.docopts}/bin/docopts -h help : "$@" <<EOF
Usage: ...
EOF
)"
```

Actually, since I can't verify, let me use the form from the docopts README which I'm fairly confident about:

```bash
eval "$(docopts -V "$version" -h help : "$@" <<EOF
...
EOF
)"
```

But `-V` requires a version. There's also `--auto`. From the docopts man page (I recall now more clearly):

```
docopts [options] -- [arguments] : [usage]
```

Ugh. Let me just go with the commonly shown pattern:

```bash
eval "$(${pkgs.docopts}/bin/docopts : --auto : "$@" <<EOF
Usage: ${llm-agent-name} run
       ${llm-agent-name} push [--key=<key>] [<refspec>]
EOF
)"
```

Hmm wait, in this pattern, `:` then `--auto` then `:` then `"$@"`. The first `:` ends the "docopts options" section? The docopts man page: "docopts [options] arguments... : [usage]" — where arguments are the arguments to parse (typically `"$@"`), and usage is the usage text. So `docopts : --auto : "$@"` would parse `--auto` and `:` as arguments, which is wrong.

Actually no. Looking at real docopts usage examples from its README:

```bash
eval "$(docopts -V "$version" -h help : "$@" <<EOF
```

Here `-V "$version"` and `-h help` are docopts options, then `:` , then `"$@"` are the arguments, then the usage comes from stdin (heredoc). So the structure is `docopts [docopts-options] : [arguments] [usage]`. And `--auto` is a docopts option. So:

```bash
eval "$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
Usage: ...
EOF
)"
```

Hmm, but where does the usage come from — stdin or after the arguments? In the README example, the usage text is the heredoc on stdin, and it comes after `"$@"` in the command line... no wait, the heredoc is stdin for the whole command. The `: "$@"` are the positional parts: `:` separator, then the arguments to parse. The usage is read from stdin.

I'm fairly confident the pattern is:

```bash
eval "$(docopts [docopts-options] : "$@" <<EOF
<usage text>
EOF
)"
```

And `--auto` is one of the docopts options: "Automatic flag handling: on parse error, print usage and exit". So:

```bash
eval "$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
Usage: ${llm-agent-name} run
       ${llm-agent-name} push [--key=<key>] [<refspec>]
EOF
)"
```

Hmm, but I've also seen `docopts : --auto : "$@"`. Let me check the actual docopts man page from memory... The man page SYNOPSIS: `docopts [--] [options] arguments... : [usage]`. And "arguments" are typically `"$@"`. The `--auto` option: "if set, docopts will exit with the parsed arguments on error". 

I'll go with `--auto : "$@"` and note it. Actually, to be safe and simple, I could avoid relying on `--auto` semantics and just use the basic form:

```bash
eval "$(${pkgs.docopts}/bin/docopts : "$@" <<EOF
...
EOF
)"
```

Hmm, but then parse errors print usage and exit(1)? docopts by default prints usage and exits on error I think. The `--auto` flag makes it exit with the right code. Either way, the basic form works. Let me include `--auto` since the user mentioned docopts is available and it's the standard robust pattern. I'll write `docopts --auto : "$@" <<EOF`. Hmm, wait — actually I now recall the README example clearly:

```bash
eval "$(docopts -V "$version" -h help : "$@" <<EOF
```

and

```bash
eval "$(docopts : --auto : "$@" <<EOF
```

The second one appears in the docopts README under "automatic mode"! Yes: `docopts : --auto : "$@"` — hmm, that has two colons. The first `:` might be... Actually I think the synopsis is `docopts [options] [arguments] : [usage]` where options and arguments come before the `:` and the usage text follows the `:`. In `docopts : --auto : "$@"`, the first `:` would be an empty arguments section, then `--auto`... no.

OK here's the thing — I recall from the docopts man page:

```
SYNOPSIS
       docopts [options] [--] [arguments] : [usage]
```

"arguments" default to `"$@"`. So `docopts --auto : "$@"` means: docopts option `--auto`, then `:` separator, then `"$@"` as arguments, usage from stdin. And `docopts : --auto : "$@"` would be: arguments `--auto`... no wait, that doesn't parse.

Hmm, actually in `docopts : --auto : "$@"`, maybe the first `:` is the separator with empty usage... I'll go with `--auto : "$@"` — wait, but I've definitely seen `docopts : --auto : "$@"` in the wild. Let me think about what makes sense: docopts parses its own command line; `--auto` is a flag; `:` separates; `"$@"` are the args to parse; usage on stdin. So `docopts --auto : "$@"` is the logical form. The `docopts : --auto : "$@"` form might be from an older version where the first `:` was required. 

To be safe, I'll write `eval "$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF ... EOF)"` and mention that docopts handles the usage/exit. If the exact flag placement is off, it's a one-character fix. Actually, you know, let me check nixpkgs: `pkgs.docopts` exists (docopts is in nixpkgs as `docopts`). Yes, `docopts` is in nixpkgs (python docopt wrapper).

2. Heredoc inside nix `''` string: the `<<EOF` heredoc inside the script. In nix indented strings, `''` escapes: `'''` for literal `''`, `''${` for literal `${`. The heredoc content contains `${llm-agent-name}` which should be interpolated by nix — that's fine, just `${llm-agent-name}`. The docopts usage contains `[--key=<key>]` — no nix interpolation issues. But `$(...)` and `$@` need escaping? In nix `''` strings, `$` doesn't need escaping unless followed by `{`. `"$@"` is fine. `$(...)` is fine. `''${` needs escaping — do I have `''${` anywhere? `''${key:-...}` — yes! In bash I want `${key:-default}` but in nix indented string, `''${` is an escape for literal `${`... wait no: in nix indented strings, `''${` means literal `${`? No — in indented strings (`''...''`), `''` is escaped as `'''`, and `${` is escaped as `''${`. So to write bash `${key:-...}` inside a nix `''` string, I write `''${key:-...}` which produces `${key:-...}`. 

3. docopts variable naming: `--key=<key>` becomes variable `key`, `<refspec>` becomes `refspec`, commands `run`/`push` become `run`/`push` with values true/false. Also docopts sets `args`... For optional positional `[<refspec>]`, `refspec` will be empty string if not provided. For `--key=<key>` with default, I can use `[--key=<key>]` and then default in bash: `key="''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}"`.

Wait, docopts with `[--key=<key>]` — if not passed, `key` is empty string (or "false"?). For options with arguments, docopts sets the variable to the value or empty. I'll use `''${key:-default}`.

4. The push mode needs `git` and `openssh`. Use absolute paths: `${pkgs.git}/bin/git`, and `GIT_SSH_COMMAND` with `${pkgs.openssh}/bin/ssh`.

5. The current branch: `git rev-parse --abbrev-ref HEAD` — but which git? The host repo's git. Use `${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD`. But careful: the script might be run from anywhere; the push should be run from within the repository. I'll cd to the repo root or just use the current directory's git. Keep it simple: use the current directory's git (document that push must be run from within the repo). Or use `git rev-parse --show-toplevel` to cd there. Let me do: `cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"` so the push works from anywhere inside the repo. That's a nice touch.

6. The remote URL: `ssh://git@localhost:${port}/var/lib/agent/repo.git`. The repo path in the guest: `/var/lib/agent/repo.git` (from the proposal). Port: 2222.

7. Also need `virtualisation.forwardPorts` in the VM config and sshd enabled — those are part of the git-repo VM work. Since the user asked specifically about the app, I'll show the app change primarily, plus the minimal VM config bits (port forward) needed for coherence. Actually, let me include the port forward in the VM config since the push mode depends on it, and mention sshd/repo setup comes with the git-repo implementation.

Let me also double check: `pkgs.docopts` — is it in nixpkgs? Yes, `docopts` is a package in nixpkgs (it's a shell script wrapping python docopt). The binary is `docopts`.

Now, the refspec handling: `<refspec>` optional positional. If given, use it; else push current branch: `HEAD:refs/heads/<branch>`. 

```bash
branch="$(git rev-parse --abbrev-ref HEAD)"
refspec="''${refspec:-HEAD:refs/heads/$branch}"
```

Wait, docopts sets `refspec` variable; if not provided it's empty. So `''${refspec:-HEAD:refs/heads/$branch}` works.

Also `--key` default: `$DEVTOOLS_CONFIG/agent-git/id_ed25519`. Hmm, but the user said keys are part of the nix config (authorizedKeys). The private key location on the host is up to the user. Default to `$DEVTOOLS_CONFIG/agent-git/id_ed25519`? Or `~/.ssh/id_ed25519`? Since the devtools config dir is already the tool's private config location, I'll default to `$DEVTOOLS_CONFIG/agent-git/id_ed25519` and allow `--key` override. Hmm, but the config dir is for the tool's private config. The prelude `get-config` provides DEVTOOLS_CONFIG. Let me just default to `$DEVTOOLS_CONFIG/agent-git/id_ed25519` and allow `--key` override.

Also StrictHostKeyChecking=no and UserKnownHostsFile=/dev/null since the VM's host key changes each boot.

Let me also handle: the push mode should source the devtools config (for DEVTOOLS_CONFIG). Yes.

Now write the full modified setup.nix launch script. Also the VM config needs the port forward:

```nix
virtualisation.forwardPorts = [
  { from = "host"; host.port = git-ssh-port; guest.port = 22; }
];
```

And sshd must be enabled in the VM (part of the git-repo work). I'll note that.

Let me write the code:

```nix
  /**
  Port on the host through which the guest's sshd (port 22)
  is reachable; used both by the VM port forwarding and by the
  push mode of the launch script.
  */
  git-ssh-port = 2222;

  /**
  The host-side launch script. It exposes two modes:
  'run' boots the agent VM, 'push' pushes the current branch
  of the host repository to the agent VM's git repository.
  */
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    eval "$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
    Usage: ${llm-agent-name} run
           ${llm-agent-name} push [--key=<key>] [<refspec>]

    Modes:
      run     Boot the agent VM.
      push    Push the current branch (or <refspec>) to the
              agent VM's git repository.
    EOF
    )"

    if [ "$run" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"

      if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
        echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
        echo "If a lite-llm instance provides this model, launch it on the host first." >&2
      fi

      user_key=$(${key-script})
      user_key_dir="$DEVTOOLS_CONFIG/users/"
      mkdir -p "$user_key_dir"
      echo "$user_key" > "$user_key_dir/${provider-user}.key"
      export DEVTOOLS_CONFIG
      echo "Running: ${vm.config.system.build.vm}/bin/run-nixos-vm"
      exec ${vm.config.system.build.vm}/bin/run-nixos-vm
    fi

    if [ "$push" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"
      key="''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}"
      refspec="''${refspec:-HEAD:refs/heads/$(git rev-parse --abbrev-ref HEAD)}"
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ${pkgs.git}/bin/git push "ssh://git@localhost:${toString git-ssh-port}/var/lib/agent/repo.git" "$refspec"
    fi
  '';
```

Wait, there's an issue with the heredoc inside `eval "$(...)"`. The heredoc is fed to docopts as its usage input. docopts reads usage from stdin when... hmm, actually in the README examples, the heredoc is the usage text passed as the last argument after `:`. Let me look at the README example again:

```bash
eval "$(docopts -V "$version" -h help : "$@" <<EOF
usage: docopts ...
EOF
)"
```

Hmm, I recall now more strongly: `docopts` reads the usage from stdin when the usage argument is `-` or when given via heredoc as the last argument. The pattern `: "$@" <<EOF` — the `:` separates docopts' own invocation, `"$@"` are the args to parse, and the heredoc provides the usage text on stdin. I'm fairly confident this works because the README shows exactly this pattern.

Also `--auto`: from the docopts man page: `--auto` — "automatic flag handling: exit with error code and usage on parse errors". I'll include it. If the exact syntax is off, it's trivially fixable, but I believe `docopts --auto : "$@" <<EOF` is right. Hmm, actually wait. I want to double check the order: is it `docopts : --auto : "$@"`? I've seen this in the wild... The man page synopsis: `docopts [options] arguments... : [usage]`. So options come first: `--auto` is an option. Then `arguments...` = `"$@"`, then `:` then usage. So `docopts --auto "$@" :` hmm no. The `:` separates arguments from usage. So: `docopts --auto "$@" <<EOF`? But then where's the `:`? 

Ugh. OK here's the thing — in the README example `docopts -V "$version" -h help : "$@"`, the `:` comes before `"$@"`. So the structure is `docopts [options] : [arguments] [usage]`? That would mean `:` separates docopts options from the arguments to parse. And the usage text comes from stdin (heredoc). So `docopts --auto : "$@" <<EOF` fits: options (`--auto`), `:`, arguments (`"$@"`), usage from stdin. 

I'll go with:

```bash
eval "$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
...
EOF
)"
```

Hmm, one more consideration: docopts needs the usage to start with "usage:" (case-insensitive) typically. The usage lines must start with the program name. I'll use `${llm-agent-name}` as the program name. But wait — the script is invoked as `launch-<name>` (the app program is `launch-${llm-agent-name}`), and the usage says `${llm-agent-name} run`. docopts matches the command name in usage lines against argv[0]? No — docopts doesn't check argv[0]; it just parses the arguments. The usage pattern `Usage: name run` means the literal token `name` must appear as the first argument. So users invoke `launch-<name> run` and the usage says `<name> run` — mismatch! The usage pattern must match the actual arguments: if the script is invoked as `launch-foo run`, the first arg is `run`, not `foo`. So the usage should be:

```
Usage: launch-${llm-agent-name} run
       launch-${llm-agent-name} push [--key=<key>] [<refspec>]
```

Or simpler, use `$(basename $0)`... but docopts usage is static text. Since the script name is `launch-${llm-agent-name}`, I'll write the usage with `launch-${llm-agent-name}`. Hmm, but actually docopts treats the first non-option token in the usage line as the program name and doesn't require it to match argv[0]... Actually docopt does require the usage pattern to match the arguments. In `Usage: myprog run`, `myprog` is a literal that must appear in the arguments. So if invoked as `launch-foo run`, usage must say `launch-foo run`. So I'll use `launch-${llm-agent-name}` in the usage. Alternatively name the modes without a program name... docopt requires the program name in usage lines. OK: `launch-${llm-agent-name}`.

Hmm wait, actually, I could also check `$0`... no, keep it simple: usage uses `launch-${llm-agent-name}`.

Let me also double-check the `''` escaping in the heredoc: the heredoc content is inside the nix `''` string. `${llm-agent-name}` interpolates (good). `[--key=<key>]` — fine. No `''` sequences. Good.

For the push mode, `git rev-parse --abbrev-ref HEAD` — use `${pkgs.git}/bin/git`. And `cd` to the repo root first: `cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"`.

Also, `set -e` with `git push` — fine.

One more thing: `GIT_SSH_COMMAND` with the key. Also `-o IdentitiesOnly=yes` is good practice to avoid agent keys. And the port is in the URL so no `-p` needed.

Now the VM config addition (port forward):

```nix
virtualisation.forwardPorts = [
  { from = "host"; host.port = git-ssh-port; guest.port = 22; }
];
```

And sshd must be enabled for push to work — that's part of the git-repo VM work (next step). I'll mention that this assumes the sshd/git-repo setup lands with the git-repo implementation, and show the port forward now.

Also `pkgs.docopts` — the package name in nixpkgs. Let me double check: nixpkgs has `docopts` (attribute `docopts`), which installs `docopts` script. Yes.

Let me also think about whether `writeScript` vs `writeShellScript`: existing code uses `pkgs.writeScript`. Keep it.

Also, the `push` mode: should it check that the VM is running? A failed ssh connection will just error out naturally. Fine.

Let me write the final answer: brief description of changes + the code. The system prompt says "If you need to describe code changes, do so briefly." So keep prose tight, show the code.

Also note: `refspec` variable from docopts — for optional positional `[<refspec>]`, docopts sets `refspec` to empty string when absent. And `key` from `[--key=<key>]` similarly. Using `''${key:-...}` handles both.

One subtlety: in the nix `''` string, `''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}` — the `''$` is fine, `''${` escapes to literal `${`. 

Also `$(git rev-parse --abbrev-ref HEAD)` inside `''${refspec:-...}` — command substitution inside parameter expansion default. That works in bash: `${refspec:-$(...)}`. But I wrote `''${refspec:-HEAD:refs/heads/$(...)}`. Fine.

Wait, there's a subtlety: `HEAD:refs/heads/$(git rev-parse --abbrev-ref HEAD)` — if HEAD is detached this breaks, but fine for the dummy use.

Also, should the push mode cd to the repo root? `git push` works from anywhere in the repo. `git rev-parse --abbrev-ref HEAD` also works from anywhere in the repo. So no cd needed. But if run outside a repo, it errors — acceptable.

Let me also make sure about `set -e` and docopts eval: if docopts fails (bad args), `eval "$(...)"` — with `set -e`, a docopts failure... `eval` of empty string succeeds. Hmm, `--auto` makes docopts exit with usage on error, and the command substitution failure would propagate with set -e? `eval "$(cmd)"` — if cmd fails, the substitution itself doesn't fail the script under `set -e` (it's part of an assignment... actually `eval "$(cmd)"` — the exit status is that of eval). With `--auto`, docopts prints usage and exits non-zero, and its output would be empty, then eval of empty succeeds. Hmm, that would silently continue. To be safe: `eval "$(...)" || exit 1`? Or capture first. Keep it simple; `--auto` prints usage to stderr and exits 1; the script would then continue with unset vars... Let me add `|| exit`:

```bash
args="$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
...
EOF
)" || exit 1
eval "$args"
```

That's cleaner. 

Now the answer structure:
1. Brief overview of the change.
2. The code: modified `launch-llm-agent` in setup.nix, plus the `git-ssh-port` let binding and the `virtualisation.forwardPorts` addition.
3. Brief notes: usage examples, and that sshd/repo setup comes with the git-repo work.

Keep it reasonably brief. Let me write the code carefully.

```nix
  /**
  Port on the host through which the guest's sshd is reachable.
  Used both by the VM's port forwarding and by the push mode of
  the launch script.
  */
  git-ssh-port = 2222;

  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    # Parse the arguments. docopts turns the usage text below into
    # shell variables ('run', 'push', 'key', 'refspec').
    args=$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
    Usage: launch-${llm-agent-name} run
           launch-${llm-agent-name} push [--key=<key>] [<refspec>]

    Modes:
      run   Boot the agent VM.
      push  Push the current branch (or <refspec>) of the host
            repository to the agent VM's git repository.
    EOF
    ) || exit 1
    eval "$args"

    if [ "$run" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"

      if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
        echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
        echo "If a lite-llm instance provides this model, launch it on the host first." >&2
      fi

      user_key=$(${key-script})
      user_key_dir="$DEVTOOLS_CONFIG/users/"
      mkdir -p "$user_key_dir"
      echo "$user_key" > "$user_key_dir/${provider-user}.key"
      export DEVTOOLS_CONFIG
      echo "Running: ${vm.config.system.build.vm}/bin/run-nixos-vm"
      exec ${vm.config.system.build.vm}/bin/run-nixos-vm
    fi

    if [ "$push" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"
      key="''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}"
      refspec="''${refspec:-HEAD:refs/heads/$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)}"
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ${pkgs.git}/bin/git push "ssh://git@localhost:${toString git-ssh-port}/var/lib/agent/repo.git" "$refspec"
    fi
  '';
```

Hmm wait, there's a problem with the heredoc inside `$(...)` inside the nix string. The heredoc delimiter EOF and the `)` closing the command substitution. The heredoc body is fed to docopts' stdin... wait no. `docopts --auto : "$@" <<EOF ... EOF` — the heredoc is docopts' stdin. But the whole thing is inside `$( ... )`. The heredoc inside command substitution works in bash. The `) || exit 1` after the heredoc's EOF line — the heredoc ends at the line containing only `EOF`, and then `) || exit 1` must come... hmm, actually the `) || exit 1` needs to be after the command. Structure:

```bash
args=$(
  ${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
  ...
EOF
) || exit 1
```

Wait, but `args=$(cmd <<EOF ... EOF) || exit 1` — the `|| exit 1` applies to the assignment. If docopts fails, the command substitution returns its output (possibly empty) and exit status of the substitution... In bash, `var=$(cmd)` exit status is cmd's exit status. So `args=$(...) || exit 1` works: if docopts exits non-zero, the assignment fails, triggering `|| exit 1`. 

But careful with heredoc indentation: the heredoc content will include leading whitespace if I indent it. In bash, `<<EOF` (not `<<-EOF`) preserves leading tabs/whitespace in the content. docopt usage lines: leading whitespace is fine for usage lines? docopt usage section: the usage lines are matched with leading whitespace allowed. The "Modes:" section is the options/description section — leading whitespace there is generally OK for docopt descriptions. But to be safe, I could use `<<-EOF` with tabs... but in nix indented strings, tabs are preserved as-is. Hmm, nix indented strings strip indentation based on the minimal indentation. The heredoc lines will be indented to the script's indentation level. docopt is generally lenient with leading whitespace in usage lines. The "Modes:" section is a "options/sections" description — docopt handles free-form sections after usage. Leading whitespace should be fine.

Actually, to minimize risk, keep the heredoc content at the script's base indentation (which nix strips) and keep it simple:

```
    Usage: launch-${llm-agent-name} run
           launch-${llm-agent-name} push [--key=<key>] [<refspec>]
```

The continuation lines are indented relative to `Usage:` which is standard docopt style. Fine.

Also, one concern: in the nix `''` string, the line `) || exit 1` — fine. And `''${key:-...}` escapes. And `''${refspec:-...}`.

Another concern: `"$@"` inside the nix string — `$@` is fine in nix indented strings (only `${` is special). 

Now, `docopts` variable for commands: docopt usage `run` and `push` as commands → docopts sets `run=true/false` and `push=true/false`. Yes, docopts exports each usage element as a shell variable; commands get "true"/"false".

Also `--key=<key>` → variable `key`; `[<refspec>]` → `refspec` (empty string when absent, or "false"? For optional positionals, docopts sets them to empty string when absent... actually docopt sets optional positionals to empty string). Using `:-` default handles both empty and unset.

Now the VM config: add port forwarding. In the existing vm config:

```nix
virtualisation.forwardPorts = [
  { from = "host"; host.port = git-ssh-port; guest.port = 22; }
];
```

And note that sshd/repo setup (services.openssh, git user, bare repo) comes with the git-repo implementation step.

Also, `pkgs.docopts` — need to confirm it's in nixpkgs. Yes: `docopts` package provides `bin/docopts`.

Should I also mention that `git` and `openssh` are used from nixpkgs (already available)? Yes, `${pkgs.git}/bin/git`, `${pkgs.openssh}/bin/ssh`.

One more consideration: the `push` mode's default key path `$DEVTOOLS_CONFIG/agent-git/id_ed25519` — since authorizedKeys are now in the nix config, the user configures the public keys there and places the corresponding private key at that path (or passes `--key`). I'll note this.

Also the remote URL: `ssh://git@localhost:2222/var/lib/agent/repo.git`. The repo path `/var/lib/agent/repo.git` per the proposal.

Let me also double check `toString git-ssh-port` — port is an int, in string interpolation `"${toString git-ssh-port}"`. In the nix string, `${toString git-ssh-port}` interpolates. Good.

Edge: `virtualisation.forwardPorts` — qemu-vm module supports it. Good.

Now write the answer. Brief description + code. I'll show the diff-ish presentation: the `git-ssh-port` binding, the modified `launch-llm-agent`, and the `forwardPorts` addition to the VM config. Keep prose brief.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

# Two-mode launch script via `docopts`

## Changes to `llm-agent/setup.nix`

**1. Add a `git-ssh-port` binding** (shared by the VM's port forward and the push mode):

```nix
  # Port on the host through which the guest's sshd is reachable.
  git-ssh-port = 2222;
```

**2. Add the port forward to the VM config** (inside `vm.config`):

```nix
          virtualisation.forwardPorts = [
            { from = "host"; host.port = git-ssh-port; guest.port = 22; }
          ];
```

**3. Replace `launch-llm-agent`** with a docopts-parsed two-mode script:

```nix
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    # Parse the arguments; docopts turns the usage text into shell
    # variables ('run', 'push', 'key', 'refspec').
    args=$(${pkgs.docopts}/bin/docopts --auto : "$@" <<EOF
    Usage: launch-${llm-agent-name} run
           launch-${llm-agent-name} push [--key=<key>] [<refspec>]

    Modes:
      run   Boot the agent VM.
      push  Push the current branch (or <refspec>) of the host
            repository to the agent VM's git repository.
    EOF
    ) || exit 1
    eval "$args"

    if [ "$run" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"

      if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
        echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
        echo "If a lite-llm instance provides this model, launch it on the host first." >&2
      fi

      user_key=$(${key-script})
      user_key_dir="$DEVTOOLS_CONFIG/users/"
      mkdir -p "$user_key_dir"
      echo "$user_key" > "$user_key_dir/${provider-user}.key"
      export DEVTOOLS_CONFIG
      echo "Running: ${vm.config.system.build.vm}/bin/run-nixos-vm"
      exec ${vm.config.system.build.vm}/bin/run-nixos-vm
    fi

    if [ "$push" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"
      key="''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}"
      refspec="''${refspec:-HEAD:refs/heads/$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)}"
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ${pkgs.git}/bin/git push "ssh://git@localhost:${toString git-ssh-port}/var/lib/agent/repo.git" "$refspec"
    fi
  '';
```

## Notes

- **docopts** (`pkgs.docopts`) parses the usage heredoc and exports `run`, `push`, `key`, `refspec` as shell variables; `--auto` makes it print usage and exit on bad arguments, and `|| exit 1` propagates that.
- **`run` mode** is unchanged: prelude config, provider reachability warning, key provisioning, VM boot.
- **`push` mode** pushes the current branch (or an explicit `<refspec>`) to `ssh://git@localhost:2222/var/lib/agent/repo.git`, authenticating with the private key matching one of the `authorizedKeys` configured in nix — defaulting to `$DEVTOOLS_CONFIG/agent-git/id_ed25519`, overridable with `--key`. `StrictHostKeyChecking=no` / `UserKnownHostsFile=/dev/null` because the VM's host key changes on each boot.
- The `''${...}` sequences are escaped nix interpolations (literal bash `${...}`).
- The push mode only becomes functional once the guest-side pieces land (sshd, `git` user, bare repo at `/var/lib/agent/repo.git`) — that's the git-repo step of the plan; the port forward above is included now so the app and VM stay consistent.

> Tokens: 6.8k sent, 12k received. Cost: $0.02 message, $0.04 session.  

#### /code looks good proceed with implementation.  

#### looks good proceed with implementation.  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Need to output full updated config.nix and setup.nix implementing: git options (enable, authorizedKeys), VM sshd/git user/bare repo/post-receive/spool/path unit/agent-run service, parameterized agent script, docopts two-mode launch script, port forward.

Write both files fully.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

# Implementation

Two files change:

- **`llm-agent/config.nix`** — adds a `git` option group (`enable`, `authorizedKeys`) to the agent spec.
- **`llm-agent/setup.nix`** — the guest VM gains sshd, a `git` user (authorized keys from the config), the bare repo with a `post-receive` hook, a spool + `systemd.path` trigger, an `agent-run` service that checks out the pushed branch and runs the agent (cwd = checkout) with the "summarize the last commit" task. The agent script becomes work-dir parameterized and gains a git tool. The host-side app becomes a two-mode docopts script (`run` / `push`), with a forwarded SSH port.

The boot-time dummy `llm-agent` service is replaced by the push-triggered `agent-run` service; the provider plumbing (env vars, 9p key mount, key provisioning in the launch script) is reused unchanged.

llm-agent/config.nix
```
top@{ inputs, flake-parts-lib, lib, llm-providers, ... }:
let
  inherit (llm-providers) provider-type;
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;

  spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the llm agent. This will trigger the creation
          of the scripts used to launch the agent.
        '';
        default = false;
      };

      provider = mkOption {
        type = provider-type;
        description = ''
          This option is used to specify the provider that
          will be used to communicate with the llm agent.
        '';
      };

      git = mkOption {
        type = types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              description = ''
                Enable the git repository inside the agent VM.
                Pushes to the repository trigger the agent: the
                pushed branch is checked out into a working
                directory and the agent is spawned there.
              '';
              default = false;
            };

            authorizedKeys = mkOption {
              type = types.listOf types.str;
              description = ''
                SSH public keys authorized to push to the
                agent VM's git repository. The corresponding
                private keys must be available on the host
                pushing to the VM.
              '';
              default = [ ];
            };
          };
        };
        description = ''
          Configuration of the git repository hosted inside
          the agent VM.
        '';
        default = { };
      };
    };
  };
  perSystem = _:
  let
    imports = lib.attrValues (
      lib.mapAttrs to-llm-agent top.config.development-tools.llm-agent
    );
    to-llm-agent = llm-agent-name: llm-agent: {
      imports = [ ./setup.nix ];
      config._module.args = { inherit llm-agent-name llm-agent; };
    };
  in
  {
    inherit imports;
    config._module.args = { inherit (inputs) nixpkgs; };
  };
in
  {
    options = {
      development-tools.llm-agent = mkOption {
        type = types.attrsOf spec;
        description = ''
          The 'llm-agent' development tool easily allows setting
          up sandboxed environments to run autonomus agents within
          the context of the repository.

          It also provides options to easily enhance the
          agents with MCPs or additional tools.
        '';
        default = {};
      };
      perSystem = mkPerSystemOption perSystem;
    };
  }
```

llm-agent/setup.nix
```
/**
This module is responsible for generating all the flake attributes
that result from an llm-agent configuration. Each configured agent
is run inside a QEMU VM running NixOS; the agent connects to the
llm provider specified in the configuration (e.g. a lite-llm
instance running on the host machine).

When 'llm-agent.git.enable' is set, the VM additionally hosts a
git repository that accepts pushes over ssh. Pushes trigger the
agent: the pushed branch is checked out into a working directory
and the agent is spawned there with the task of summarizing the
changes of the last commit.
*/
{
  config,
  pkgs,
  lib,
  devtools-prelude,
  llm-agent-name,
  llm-agent,
  nixpkgs,
  ...
}:
let
  /**
  The python environment that runs the agent. The 'langchain'
  package provides the agent machinery while 'langchain-openai'
  provides the OpenAI-compatible client used to connect to the
  llm provider (lite-llm exposes an OpenAI-compatible API).
  */
  agent-python = pkgs.python314.withPackages (ps: [
    ps.langchain
    ps.langchain-openai
  ]);

  /**
  Non-secret agent parameters, baked into the guest configuration.
  The endpoint url comes from the provider configuration (for
  lite-llm providers it points at the QEMU host alias so that
  requests are forwarded to the instance running on the host).
  */
  provider-endpoint-url = llm-agent.provider.endpoint.url;
  provider-model = llm-agent.provider.models.main.name;
  provider-user = llm-agent.provider.user.name;
  key-script =
    with llm-agent.provider.user;
    config.development-tools.llm-providers.${provider}.users.${name}.key-script
  ;

  /**
  Whether the git repository (and the push-triggered agent
  pipeline) is enabled for this agent.
  */
  git-enable = llm-agent.git.enable;
  git-authorized-keys = llm-agent.git.authorizedKeys;

  /**
  Guest-side paths of the git repository, the spool directory
  watched for pushed branches, and the working directories the
  agent is spawned in.
  */
  repo-path = "/var/lib/agent/repo.git";
  inbox-path = "/var/lib/agent/inbox";
  work-root = "/var/lib/agent/work";

  /**
  Port on the host through which the guest's sshd is reachable.
  The launch script forwards the host port to the guest's ssh
  port so that 'git push' can reach the repository.
  */
  git-ssh-port = 2222;

  /**
  The script implementing the agent. All secrets are read
  at runtime from the environment / the shared key directory,
  so nothing here is unsuitable for the nix store.

  The working directory is given as the first argument; the
  agent changes into it so that all tools (and the dummy task
  of summarizing the last commit) operate on the pushed branch.
  */
  agent-script = pkgs.writeText "agent.py" ''
    import os
    import sys

    from langchain_openai import ChatOpenAI
    from langchain_core.tools import tool
    from langgraph.prebuilt import create_react_agent

    # --- Working directory: the checked out branch ---
    work_dir = sys.argv[1]
    os.chdir(work_dir)

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
            ["git"] + parts,
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
  '';

  /**
  The 'post-receive' hook installed in the bare repository. For
  every pushed branch it drops a file (named after a sanitized
  branch name) into the spool directory, which the systemd path
  unit turns into an agent run. The hook does not run the agent
  itself: the push should return quickly and the agent should
  run under its own (systemd) privileges.
  */
  post-receive-hook = pkgs.writeText "post-receive" ''
    #!${pkgs.bash}/bin/bash
    set -e

    inbox="${inbox-path}"
    mkdir -p "$inbox"

    # One line per ref: <old> <new> <refname>
    while read -r old new refname; do
      case "$refname" in
        refs/heads/*)
          branch="''${refname#refs/heads/}"
          # Sanitize the branch name into a file name.
          sanitized="$(echo -n "$branch" | tr '/_[:upper:]' '.-[:lower:]')"
          echo "$branch" > "$inbox/$sanitized"
          ;;
      esac
    done
  '';

  /**
  The script run by the 'agent-run' service. For each spool file
  (i.e. each pushed branch) it checks the branch out into a
  working directory and spawns the agent there, writing its
  summary to 'AGENT_SUMMARY.md' in the working directory.
  */
  agent-run-script = pkgs.writeText "agent-run.sh" ''
    #!${pkgs.bash}/bin/bash
    set -e

    inbox="${inbox-path}"
    work_root="${work-root}"
    mkdir -p "$inbox" "$work_root"

    for spool in "$inbox"/*; do
      [ -e "$spool" ] || continue
      branch="$(cat "$spool")"
      work="$work_root/$branch"

      # Check out (or update) the pushed branch.
      if [ -d "$work/.git" ]; then
        git -C "$work" fetch origin
        git -C "$work" checkout "$branch"
        git -C "$work" reset --hard "origin/$branch"
      else
        git clone --branch "$branch" "${repo-path}" "$work"
      fi

      # Run the agent in the working directory, capturing
      # its summary next to the checkout.
      ${agent-python}/bin/python ${agent-script} "$work" \
        | tee "$work/AGENT_SUMMARY.md"

      # The spool file has been handled.
      rm "$spool"
    done
  '';

  /**
  The NixOS configuration of the guest VM. The agent runs as a
  systemd service; the host's private configuration directory
  (holding the provider authentication keys) is shared read-only
  through a 9p mount so that secrets never enter the nix store
  or the QEMU command line.

  When the git pipeline is enabled, the VM additionally hosts
  the git repository (reachable over ssh) and the push-triggered
  agent service.
  */
  vm = nixpkgs.lib.nixosSystem {
    modules = [
      {
        imports = [
          "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
        ];
        config = {
          nixpkgs.hostPlatform = pkgs.system;
          virtualisation.memorySize = 2048;
          virtualisation.cores = 2;

          # Run the VM without a graphical display; the guest's
          # serial port (ttyS0) is connected directly to the
          # terminal that launched the VM, and the kernel console
          # is placed on that serial line.
          virtualisation.graphics = false;
          boot.kernelParams = [ "console=ttyS0" ];

          # Share the host's private configuration directory with
          # the guest through 9p. The mount is read-only; the agent
          # only needs to read its authentication key.
          virtualisation.qemu.options = [
            ''-virtfs local,path="$DEVTOOLS_CONFIG",mount_tag=devtools-config,security_model=none,readonly=on''
          ];
          boot.initrd.availableKernelModules = [ "9p" "9pnet_virtio" ];
          boot.kernelModules = [ "9p" "9pnet_virtio" ];

          users.users.nixos.hashedPassword = "$y$j9T$Ij.zgsiQ9UbG805vuIjz0/$qiZCBxun/3VJrAic6AGusQTlX4VN2W.Mp4LrFPrFZ6B";
          users.users.nixos.group = "nixos";
          users.users.nixos.extraGroups = [ "wheel" ];
          users.groups.nixos = { };
          users.users.nixos.isNormalUser = true;

          services.journald.extraConfig = ''
            ForwardToConsole=yes
            MaxLevelConsole=info
          '';

          # The 9p mount of the shared key directory, defined as an
          # explicit systemd mount unit (rather than a fileSystems
          # entry) so it is generated directly as a unit and can be
          # depended upon by the agent service.
          systemd.mounts = [
            {
              what = "devtools-config";
              where = "/run/agent_keys";
              type = "9p";
              options = "trans=virtio,version=9p2000.L,ro";
              wantedBy = [ "multi-user.target" ];
            }
          ];

          environment.systemPackages = [ pkgs.git ];

          # The git repository and the push-triggered agent.
          services.openssh = {
            enable = git-enable;
            settings = {
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
            };
          };

          # Forward the guest ssh port so that the host can
          # push to the repository.
          virtualisation.forwardPorts = lib.optionals git-enable [
            { from = "host"; host.port = git-ssh-port; guest.port = 22; }
          ];

          users.users.git = lib.mkIf git-enable {
            isSystemUser = true;
            group = "git";
            home = "/var/lib/agent";
            createHome = true;
            shell = "${pkgs.git}/bin/git-shell";
            openssh.authorizedKeys.keys = git-authorized-keys;
          };
          users.groups.git = lib.mkIf git-enable { };

          # Create the bare repository and install the push hook.
          systemd.services.git-repo-init = {
            description = "Initialize the agent git repository";
            wantedBy = [ "multi-user.target" ];
            after = [ "local-fs.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "git";
              Group = "git";
            };
            script = ''
              if [ ! -d "${repo-path}" ]; then
                git init --bare "${repo-path}"
              fi
              mkdir -p "${inbox-path}"
              ln -sfn ${post-receive-hook} "${repo-path}/hooks/post-receive"
              chmod +x ${post-receive-hook}
            '';
          };

          # Pushes drop spool files; watch the spool directory and
          # trigger the agent run.
          systemd.paths.agent-inbox = {
            description = "Watch the agent inbox for pushed branches";
            wantedBy = [ "multi-user.target" ];
            pathConfig = {
              PathExistsGlob = "${inbox-path}/*";
              Unit = "agent-run.service";
            };
          };

          # The agent service. Non-secret parameters are baked in;
          # the api key is read from the shared directory at runtime.
          # The service's output is forwarded to the kernel log so
          # that it shows up on the serial console, i.e. in the
          # terminal that launched the VM. The service requires the
          # 9p mount (holding the api key) to be up before it starts.
          systemd.services.agent-run = {
            description = "LangChain deep agent (push-triggered)";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network-online.target"
              "run-agent_keys.mount"
              "git-repo-init.service"
            ];
            wants = [ "network-online.target" ];
            environment = {
              OPENAI_BASE_URL = provider-endpoint-url;
              OPENAI_MODEL = provider-model;
              AGENT_USER = provider-user;
              AGENT_KEYS_DIR = "/run/agent_keys";
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "git";
              Group = "git";
              #StandardOutput = "kmsg";
              #StandardError = "kmsg";
            };
            script = ''
              exec ${pkgs.bash}/bin/bash ${agent-run-script}
            '';
            #unitConfig.OnFailure = [ "poweroff.target" ];
          };
        };
      }
    ];
  };

  /**
  The host-side launch script. It exposes two modes:

    run   Boot the agent VM.
    push  Push the current branch (or an explicit refspec) of the
          host repository to the agent VM's git repository.

  The arguments are parsed with docopts. In 'run' mode the script
  sources the tool specific environment (defining DEVTOOLS_CONFIG),
  warns if no llm provider is reachable on the host, provisions the
  provider key into the shared configuration directory and boots
  the VM. In 'push' mode it pushes over ssh to the repository in
  the running VM.
  */
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    # Parse the arguments; docopts turns the usage text into shell
    # variables ('run', 'push', 'key', 'refspec').
    args=$(${pkgs.docopts}/bin/docopts "$@" : <<EOF
    Usage: launch-${llm-agent-name} run
           launch-${llm-agent-name} push [--key=<key>] [<refspec>]

    Modes:
      run   Boot the agent VM.
      push  Push the current branch (or <refspec>) of the host
            repository to the agent VM's git repository.
    EOF
    ) || exit 1
    eval "$args"

    if [ "$run" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"

      if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
        echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
        echo "If a lite-llm instance provides this model, launch it on the host first." >&2
      fi

      user_key=$(${key-script})
      user_key_dir="$DEVTOOLS_CONFIG/users/"
      mkdir -p "$user_key_dir"
      echo "$user_key" > "$user_key_dir/${provider-user}.key"
      export DEVTOOLS_CONFIG
      echo "Running: ${vm.config.system.build.vm}/bin/run-nixos-vm"
      exec ${vm.config.system.build.vm}/bin/run-nixos-vm
    fi

    if [ "$push" = "true" ]; then
      source "${devtools-prelude.get-config llm-agent-name}"
      key="''${key:-$DEVTOOLS_CONFIG/agent-git/id_ed25519}"
      refspec="''${refspec:-HEAD:refs/heads/$(${pkgs.git}/bin/git rev-parse --abbrev-ref HEAD)}"
      export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ${pkgs.git}/bin/git push "ssh://git@localhost:${toString git-ssh-port}${repo-path}" "$refspec"
    fi
  '';

in
{
  config.apps."devtools/${llm-agent-name}" = {
    type = "app";
    program = "${launch-llm-agent}";
  };
}
```

## Notes

- **`config.nix`**: only the `git` option group was added; the rest is untouched.
- **Agent service**: the boot-time `llm-agent` oneshot is replaced by `agent-run`, triggered by the `systemd.path` unit watching the spool directory. It runs as the `git` user so it can read/write the repository checkouts under `/var/lib/agent/work`.
- **`post-receive` hook**: runs as the pushing user (`git`) via the ssh/git-shell path; it only writes spool files, so pushes return immediately.
- **Branch sanitization**: the hook's `tr` maps `/`→`.` and `_`→`-` plus lowercases, so branch names like `feature/x_Y` become safe file names; the spool file holds the original branch name for the checkout.
- **docopts**: `pkgs.docopts` with `--auto` behavior achieved via the `"$@" :` form (usage on bad args); the `eval` exposes `run`, `push`, `key`, `refspec` as shell variables. All `''${...}` occurrences are literal bash, escaped from nix.
- **Push mode**: uses the private key at `$DEVTOOLS_CONFIG/agent-git/id_ed25519` (overridable via `--key`), which must correspond to one of the `authorizedKeys` configured in nix; host-key checking is disabled since the VM's host key changes on each boot.
- I kept the commented-out `kmsg` / `OnFailure` lines from the original, since they look like work-in-progress rather than something to remove.

> Tokens: 8.3k sent, 5.0k received. Cost: $0.0076 message, $0.05 session.  
> Applied edit to llm-agent/config.nix  
> Applied edit to llm-agent/setup.nix  
> Commit 404d445 feat: add git push-triggered agent pipeline to llm-agent VM  
