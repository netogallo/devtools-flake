
# aider chat started at 2026-10-21 13:37:34

> /nix/store/c4vc8qhlrddf9lm0d31nq9imm4hvpd7k-aider-chat-0.86.1/bin/aider --read /tmp/tmp.m1nY4NJSNs --read journal/feature/agentic-dev/tasks/langchain sandbox --llm-history-file journal/feature/agentic-dev/session-contexts/langchain sandbox/llm.history --chat-history-file journal/feature/agentic-dev/session-contexts/langchain sandbox/session.md  
> Aider v0.86.1  
> Model: openrouter/z-ai/glm-5.3 with whole edit format  
> Git repo: .git with 47 files  
> Repo-map: using 4096 tokens, auto refresh  
> Added journal/feature/agentic-dev/tasks/langchain sandbox to the chat (read-only).  
> Added ../../../../tmp/tmp.m1nY4NJSNs to the chat (read-only).  

#### /ask  
> Aider v0.86.1  
> Model: openrouter/z-ai/glm-5.3 with ask edit format  
> Git repo: .git with 47 files  
> Repo-map: using 4096 tokens, auto refresh  
> Added journal/feature/agentic-dev/tasks/langchain sandbox to the chat (read-only).  
> Added ../../../../tmp/tmp.m1nY4NJSNs to the chat (read-only).  

#### How can I create a nix derivation that runs QEmu with a nixos system?  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Explain nixos-generators / qemu derivation approach.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

There are a few common approaches, depending on how much control you want:

## 1. `nixos-generators` (easiest)

Add `nixos-generators` to your flake inputs, then:

```nix
nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix" # gives you a ready-to-boot VM
    ./configuration.nix
  ];
};
```

Then `nix build .#nixosConfigurations.vm.config.system.build.vm` produces a script that launches QEMU with the right kernel/initrd/cmdline.

## 2. A custom derivation wrapping QEMU

If you want a derivation that *runs* QEMU (e.g. as a tool in your repo, which fits your `llm-agent` sandbox task):

```nix
pkgs.runCommand "qemu-vm-runner" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
  ''
    mkdir -p $out/bin
    makeWrapper ${pkgs.qemu}/bin/qemu-system-x86_64 $out/bin/run-vm \
      --add-flags "-m 4096 -smp 2" \
      --add-flags "-drive file=$out/disk.qcow2,if=virtio" \
      --add-flags "-netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0"
  ''
```

## 3. `pkgs.vmTools` / `makeTest` (for testing)

`nixpkgs#nixosTests` / `makeTestPyhton` from `nixos/lib/test-instrumentation.nix` spawn QEMU VMs with a NixOS guest — good for automated runs, but heavyweight.

## Recommendation for your task

Since your task is spawning a VM that runs a LangChain deep agent, the cleanest path is:

1. Define a NixOS configuration with a systemd service running the agent (using your existing `llm-agent/config.nix` / `setup.nix`).
2. Build it with `config.system.build.vm` (the `qemu-vm.nix` module) or `nixos-generators` to get a `qcow2` + launcher.
3. Wrap the launcher in a small derivation that exposes it as a "tool" (e.g. a script the agent/dev can invoke), forwarding the LLM provider config (API keys, endpoint) via environment variables or a shared directory.

If you share `llm-agent/config.nix` and `llm-agent/setup.nix`, I can sketch how to wire them into the VM's NixOS configuration.

> Tokens: 894 sent, 666 received. Cost: $0.0010 message, $0.0010 session.  
> llm-agent/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> llm-agent/setup.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

User already added them earlier. Suggest other files to add.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

I can see `llm-agent/config.nix` and `llm-agent/setup.nix` from earlier in the chat. To wire up the QEMU sandbox properly, it would help to also add:

1. **`flake.nix` / `flakeModule.nix`** — to see how modules are composed and where `perSystem` outputs land (e.g. `packages` or `apps`), so the VM launcher can be exposed as a dev tool.
2. **`llm-providers/config.nix` and `llm-providers/prelude.nix`** — since `provider-type` comes from there, I need to know its shape (API key, endpoint, model name) to pass provider config into the VM.
3. **`lite-llm/config.nix` / `lite-llm/setup.nix`** — if the agent connects through LiteLLM, this shows the existing pattern for a similar tool I can mirror.
4. **`presets/flakeModule.nix`** and **`prelude/config.nix`** — to understand your module conventions (e.g. how `development-tools` options are aggregated).

A quick note on what I see so far:

- `config.nix` maps each `llm-agent` attrset entry into a `perSystem` import of `setup.nix`, passing `llm-agent-name` and `llm-agent` (the option subtree) as module args.
- `setup.nix` is currently a stub (`x = 42;`, empty config) — so the VM/agent logic is entirely to be built there.

Once you add the files above, I can sketch the `setup.nix` that:
- builds a NixOS VM (via `qemu-vm.nix` or a custom QEMU wrapper derivation),
- injects the agent as a systemd service inside the guest,
- forwards the provider config (from `llm-agent.provider`) into the guest environment.

> Tokens: 1.9k sent, 474 received. Cost: $0.00081 message, $0.0018 session.  
> flake.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> flakeModule.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> lite-llm/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> lite-llm/setup.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> llm-providers/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> llm-providers/prelude.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> prelude/config.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  
> presets/flakeModule.nix  
> Add file to the chat? (Y)es/(N)o/(A)ll/(S)kip all/(D)on't ask again [Yes]: y  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

I have all files. Summarize understanding and propose design for setup.nix.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

I now have the full picture. No other files are strictly needed, though if you have an `examples/flakeModule.nix` that shows how a consumer flake configures `development-tools`, that would help confirm the intended usage pattern.

## What I understand

- **Module composition**: `flakeModule.nix` imports `llm-agent/config.nix`, which defines `development-tools.llm-agent` (attrs of `spec`, each with `enable` and `provider`), and for each entry imports `setup.nix` per-system with `llm-agent-name`/`llm-agent` as module args.
- **Provider plumbing**: `llm-providers/prelude.nix` defines `provider-type` (endpoint + user + models), and `lite-llm/config.nix` populates `development-tools.llm-providers` from its instances. So an `llm-agent` entry references a provider (e.g. a LiteLLM instance) by name.
- **Conventions**: tools expose an app at `config.apps."devtools/<name>"` (as `lite-llm/setup.nix` does), use `devtools-prelude.get-config` for private per-tool config (keys never in the store), and read secrets from files in `$DEVTOOLS_CONFIG` at launch time.

## Proposed design for `llm-agent/setup.nix`

1. **Guest NixOS config**: a small `nixosSystem` evaluation importing `qemu-vm.nix`, with a systemd service running the LangChain deep agent on a dummy task, and the LLM endpoint/model baked in from `llm-agent.provider`.
2. **Credentials**: since keys must not enter the store, the host launch script (mirroring `lite-llm/setup.nix`) sources `devtools-prelude.get-config`, reads the key file, and passes it into the guest — e.g. via QEMU `-smbios`/`-fw_cfg`, a 9p/virtfs share of `$DEVTOOLS_CONFIG`, or simply `hostfwd` so the agent talks to a LiteLLM proxy running on the host.
3. **App output**: `config.apps."devtools/${llm-agent-name}"` wrapping the QEMU launch, consistent with the LiteLLM tool.

The simplest credential story: run LiteLLM on the host (it already handles keys) and have the VM's agent connect to `10.0.2.2:<port>` (QEMU's host alias) — no secrets in the guest at all.

Want me to draft `setup.nix` along these lines?

> Tokens: 7.7k sent, 610 received. Cost: $0.0015 message, $0.0033 session.  
> examples/flakeModule.nix  
> Add file to the chat? (Y)es/(N)o/(D)on't ask again [Yes]: y  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Summarize understanding, propose design, offer draft.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

That completes the picture — no further files needed. The example confirms the intended usage:

```nix
config.development-tools.llm-agent.prelude-llm-agent = {
  enable = true;
  provider = with config.development-tools.llm-providers.prelude-lite-llm; {
    endpoint = endpoint;
    user = users.alice;
    models.main = models.master;
  };
};
```

## Observations relevant to the implementation

1. **Provider shape**: `provider-type` requires `endpoint` (with `type`/`url`), `user`, and `models.main`. Note the LiteLLM provider currently sets `url = ""` — so `setup.nix` will need a real URL (e.g. `http://10.0.2.2:4000` for the QEMU host alias) or the LiteLLM config needs fixing to emit it.

2. **Authentication**: the agent in the guest needs the user's key (e.g. `alice`'s key from `$DEVTOOLS_CONFIG/users/alice.key` on the host). Since keys must never enter the nix store, the launch script should read it at runtime — either pass it into the guest via `-fw_cfg`/kernel cmdline, or better, mount `$DEVTOOLS_CONFIG` read-only via 9p/virtfs.

3. **Structure of `setup.nix`** (mirroring `lite-llm/setup.nix`):
   - Evaluate a NixOS system: `nixpkgs.lib.nixosSystem` with `qemu-vm.nix` plus a small module defining a systemd service running the LangChain deep agent with a dummy task.
   - The agent's config (endpoint URL, model name, user) is baked into the guest config from `llm-agent.provider` — these are non-secret.
   - The API key is injected at launch time by the host wrapper script, which sources `devtools-prelude.get-config ${llm-agent-name}`.
   - Expose `config.apps."devtools/${llm-agent-name}"` running the VM launcher.

4. **Open question**: how should the agent's Python environment be built? Options are a `python3.withPackages` with `langchain`/`langgraph` (nixpkgs availability may be limited), or a `uv`/`pip`-based environment fetched at build time. This is likely the trickiest part.

Shall I draft `llm-agent/setup.nix` with this design?

> Tokens: 8.7k sent, 586 received. Cost: $0.0015 message, $0.0048 session.  

#### Use python314.withPackages. Use the 'langchain' package from nixpkgs and the 'langchain-openai' package to connect with litellm. Can you propose an implementation plan with this information?\  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Provide implementation plan for llm-agent/setup.nix using python314.withPackages, langchain + langchain-openai, connecting to litellm.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

## Implementation Plan for `llm-agent/setup.nix`

### 1. Python environment (guest)

```nix
agent-python = pkgs.python314.withPackages (ps: [
  ps.langchain
  ps.langchain-openai
]);
```

Note: verify `langchain` and `langchain-openai` exist in your nixpkgs revision (`nix search nixpkgs langchain`). If `langchain-openai` is missing, we may need `python314Packages.callPackage` with a small overlay or fall back to `python3.withPackages` on a pinned nixpkgs.

### 2. Agent script (dummy task)

A `pkgs.writeText "agent.py"` (or `writeScript`) that:

- Reads `OPENAI_API_KEY` and `OPENAI_BASE_URL` from the environment (langchain-openai's standard interface — LiteLLM exposes an OpenAI-compatible API).
- Builds a `ChatOpenAI(model = <provider.models.main.model>, base_url, api_key)`.
- Runs a dummy task, e.g. a simple LangGraph/LangChain agent asked to "list the files in /tmp and summarize what you see", printing the result to stdout/journal.

Model name and endpoint URL are **non-secret**, so they can be baked into the guest systemd service:

```nix
agent-config = {
  base-url = "http://10.0.2.2:${toString litellm-port}";  # QEMU host alias
  model = llm-agent.provider.models.main.model;
  user = llm-agent.provider.user.name;
};
```

### 3. Guest NixOS configuration

```nix
vm = nixpkgs.lib.nixosSystem {
  system = pkgs.system;
  modules = [
    "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"
    ({ ... }: {
      services.llm-agent = {  # systemd service
        enable = true;
        script = "${agent-python}/bin/python ${agent-script}";
        environment = {
          OPENAI_BASE_URL = agent-config.base-url;
          OPENAI_MODEL = agent-config.model;
          # OPENAI_API_KEY injected at launch, not here
        };
      };
      # 9p mount of the shared key directory (read-only)
      fileSystems."/run/agent-keys" = { ... };
    })
  ];
};
```

The API key is delivered via a **9p/virtfs share** of `$DEVTOOLS_CONFIG` (host) mounted read-only in the guest; the service's `ExecStartPre` reads `users/${user}.key` into `OPENAI_API_KEY` via a `EnvironmentFile` or a small pre-script. This keeps the key out of the nix store and out of the QEMU command line.

### 4. Host launch script

Mirroring `lite-llm/setup.nix`:

```nix
launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
  #!${pkgs.bash}/bin/bash
  set -e
  source "${devtools-prelude.get-config llm-agent-name}"
  exec ${vm.config.system.build.vm}/bin/run-vm-... \
    -virtfs local,path=$DEVTOOLS_CONFIG,mount_tag=agent-keys,security_model=none,readonly=on
'';
```

(The `qemu-vm.nix` module produces `config.system.build.vm`, a script that boots the VM; we append the virtfs flag. Alternatively, set `virtualisation.qemu.options` in the guest config so the share is part of the VM definition itself — cleaner.)

### 5. Output

```nix
config.apps."devtools/${llm-agent-name}" = {
  type = "app";
  program = "${launch-llm-agent}";
};
```

### 6. Prerequisite fix

`lite-llm/config.nix`'s `to-llm-provider` sets `url = ""`. It should emit the real URL (e.g. `http://10.0.2.2:${toString port}`) so `llm-agent.provider.endpoint.url` is meaningful. Also, `provider-type` currently has no `port` — the URL can carry it.

### 7. Suggested order of work

1. Fix `to-llm-provider` to emit a usable URL.
2. Build the guest NixOS VM with a trivial service (echo task) — verify it boots and reaches the host via `10.0.2.2`.
3. Add the Python agent with the dummy task, connecting through LiteLLM.
4. Wire the 9p key share and the host launch script.
5. Expose the app and test end-to-end with `nix run .#devtools.prelude-llm-agent` (with LiteLLM running on the host).

Shall I start drafting the actual code, beginning with the guest VM module?

> Tokens: 9.3k sent, 1.1k received. Cost: $0.0023 message, $0.0071 session.  

#### How will the "agent-script" be implemented?  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Explain the agent.py implementation: LangChain deep agent with dummy task, reading env vars.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

## `agent-script` Implementation

It will be a Python file generated with `pkgs.writeText "agent.py"`, run by the `python314.withPackages` environment inside the guest. Since the endpoint, model, and user name are non-secret, they're passed via environment variables set in the systemd service (baked into the guest config), and the API key is read at runtime from the 9p-mounted key directory.

### Structure

```python
import os
from langchain_openai import ChatOpenAI

# --- Configuration (injected by the systemd service) ---
base_url = os.environ["OPENAI_BASE_URL"]   # e.g. http://10.0.2.2:4000
model     = os.environ["OPENAI_MODEL"]     # e.g. openrouter/mistralai/devstral-2512
user      = os.environ["AGENT_USER"]       # e.g. alice

# --- API key: read at runtime from the shared config dir ---
key_file = os.path.join(os.environ["AGENT_KEYS_DIR"], "users", f"{user}.key")
with open(key_file) as f:
    api_key = f.read().strip()

# --- LLM client via LiteLLM's OpenAI-compatible API ---
llm = ChatOpenAI(
    model=model,
    base_url=base_url,
    api_key=api_key,
)

# --- Dummy task ---
# A minimal "deep agent" loop: the agent receives a task, plans,
# executes one tool call, and reports the result.
from langchain_core.tools import tool

@tool
def list_files(directory: str) -> str:
    """List the files in the given directory."""
    return "\n".join(sorted(os.listdir(directory)))

tools = [list_files]

# Simple agent loop (or langgraph's create_react_agent if available
# in nixpkgs' langchain package)
from langchain.agents import create_agent  # or equivalent for the installed version

agent = create_agent(llm, tools)

result = agent.invoke({
    "messages": [("user",
        "List the files in /tmp and briefly summarize what you find.")]
})

for message in result["messages"]:
    print(message.content)
```

### Key points

1. **Secrets**: the key is read from `AGENT_KEYS_DIR` (the 9p mount of the host's `$DEVTOOLS_CONFIG`), never embedded in the script or the store. The LiteLLM custom authenticator validates it against the same file on the host side.

2. **LiteLLM compatibility**: LiteLLM's proxy exposes an OpenAI-compatible API, so `ChatOpenAI` with `base_url` pointed at the LiteLLM instance is all that's needed — no LiteLLM-specific client.

3. **Dummy task**: deliberately trivial (list `/tmp`, summarize) — enough to exercise the full chain (VM → agent → LiteLLM → provider → response) without needing real tools.

4. **Agent API caveat**: the exact agent constructor depends on what nixpkgs' `langchain` version ships (`create_agent`, `create_react_agent`, or the langgraph-based deep agent API). The first implementation step should be checking the package's version and using the matching API; the loop above is easily adapted.

5. **Generation in Nix**: since only env vars are read, the script is fully static — `pkgs.writeText "agent.py" ''...''` with no interpolation of secrets, keeping it store-safe.

Want me to draft the full `setup.nix` including this script and the systemd service?

> Tokens: 10k sent, 816 received. Cost: $0.0020 message, $0.0091 session.  

#### Litellm will currently run in the host machine, how are you forwarding the requests from the vm to the host litellm instance?  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Explain QEMU user networking 10.0.2.2.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

## VM → Host LiteLLM Forwarding

The mechanism is **QEMU's user-mode networking (SLIRP)**, which the `qemu-vm.nix` module enables by default.

### How it works

With user networking, QEMU creates a virtual network for the guest:

- The guest gets address `10.0.2.15` and uses `10.0.2.2` as its **gateway — which maps directly to the host machine's loopback**.
- Any connection the guest makes to `10.0.2.2:<port>` is translated by QEMU into a connection to `127.0.0.1:<port>` on the host.

So if LiteLLM runs on the host at `localhost:4000`, the agent inside the VM simply connects to:

```
http://10.0.2.2:4000
```

No port forwarding flags, no extra QEMU options, no host firewall changes needed — this is the standard, zero-configuration path for guest→host traffic.

### Where this lands in the implementation

1. **`lite-llm/config.nix`** — `to-llm-provider` should emit the URL with the host alias:
   ```nix
   to-llm-provider = name: llm-config: {
     endpoint = {
       type = "litellm";
       url = "http://10.0.2.2:${toString llm-config.port}";
     };
   };
   ```
   (This is the fix mentioned earlier — currently `url = ""`.)

2. **Guest systemd service** — sets `OPENAI_BASE_URL` from `llm-agent.provider.endpoint.url`, so the agent's `ChatOpenAI(base_url=...)` points at `10.0.2.2:4000`.

3. **Host launch script** — the only requirement is that LiteLLM is already running on the host (e.g. via `nix run .#devtools.prelude-lite-llm`). The launch script can check this and warn:
   ```bash
   if ! ${pkgs.curl}/bin/curl -s "http://127.0.0.1:4000" >/dev/null; then
     echo "Warning: no LiteLLM instance reachable on the host at port 4000." >&2
   fi
   ```

### Caveats

- **Direction matters**: `10.0.2.2` works guest→host only. Host→guest would need `hostfwd=tcp::2222-:22` (not needed here, since the agent initiates all requests).
- **LiteLLM must bind on localhost or all interfaces**: since QEMU connects from the host's own loopback, LiteLLM listening on `127.0.0.1:4000` (its default) is sufficient.
- **Alternative considered**: running LiteLLM *inside* the VM would avoid this entirely, but keeping it on the host matches your current setup and means one LiteLLM instance can serve both host tools and sandboxed agents.

> Tokens: 11k sent, 713 received. Cost: $0.0019 message, $0.01 session.  

#### /code looks good, implement  

#### looks good, implement  

<thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

Implement: fix lite-llm/config.nix URL, and write llm-agent/setup.nix fully. Need nixpkgs input in setup.nix — setup.nix receives module args from config.nix perSystem; config.nix has `top` with `self`... flake inputs aren't directly available. Hmm. In flake-parts, perSystem gets `pkgs` etc. To evaluate nixosSystem we need nixpkgs lib — we can use `pkgs` path? Use `(import pkgs.path {}).lib`? Actually `pkgs.path` gives nixpkgs source; `import pkgs.path { system = ...; }` works but impure-ish; better: `nixosSystem` via `pkgs.lib.nixosSystem`? pkgs.lib doesn't have nixosSystem. Common trick: `import "${toString pkgs.path}/nixos/lib/eval-config.nix"`. Simpler: use `import pkgs.path { system = pkgs.system; }` then `.nixosSystem`? nixpkgs default output has `lib.nixosSystem`. Yes: `let npkgs = import pkgs.path { system = pkgs.system; }; in npkgs.lib.nixosSystem {...}`. That's acceptable.

Guest config: import "${pkgs.path}/nixos/modules/virtualisation/qemu-vm.nix" plus a module defining systemd service and 9p mount. qemu-vm.nix supports `virtualisation.qemu.options` for extra flags; mount via fileSystems with virtfs? qemu-vm.nix has `virtualisation.sharedDirs`? Newer nixpkgs qemu-vm.nix has `virtualisation.qemu.options` and 9p support via `virtualisation.sharedDirs` in some versions. I'll use virtualisation.qemu.options with -virtfs and a fileSystems entry with fsType "9p".

Write setup.nix with:
- agent-python = pkgs.python314.withPackages [ langchain langchain-openai ]
- agent-script writeText
- vm = nixosSystem with modules
- launch script sourcing devtools-prelude.get-config, checking litellm reachable, exec vm.config.system.build.vm (script run-<system>-vm). system.build.vm is a derivation with bin/run-<sys>-vm.

Also fix lite-llm/config.nix to-llm-provider url.

Write files.

</thinking-content-7bbeb8e1441453ad999a0bbba8a46d4b>

I will make two changes:

1. **`lite-llm/config.nix`** — fix `to-llm-provider` to emit a real URL (`http://10.0.2.2:<port>`, the QEMU host alias) so `llm-agent.provider.endpoint.url` is meaningful.
2. **`llm-agent/setup.nix`** — implement the full sandbox: a NixOS VM (via `qemu-vm.nix`) running a systemd service with the LangChain deep agent on a dummy task, a `python314.withPackages` environment with `langchain`/`langchain-openai`, a 9p read-only share of `$DEVTOOLS_CONFIG` for the API key (never in the store), and a host launch script exposing `config.apps."devtools/<name>"`.

lite-llm/config.nix
```
# This module allows configuring instances of llm lite
top@{ self, lib, config, flake-parts-lib, ... }:
let
  inherit (lib) types mkOption;
  inherit (flake-parts-lib) mkPerSystemOption;

  # This submodule will be used
  # to configure the settings of the
  # modules that the llm-lite configuration
  # will be serving.
  model-spec = types.submodule {
    options = {
      model = mkOption {
        type = types.str;
        description = ''
          The name of the model. This formatter as '<provider>/<model vendor>/model'. As
          an example 'openrouter/openai/gpt-4'.
        '';
      };
    };
  };

  # This submodule configures a user that is allowed
  # to authenticate against the llm-lite instance. No
  # options are defined yet; the submodule exists so that
  # per-user settings (e.g. rate limits) can be added
  # later without changing the shape of the configuration.
  # The authentication key is deliberately not an option:
  # keys are generated when the instance is launched and
  # never enter the nix store.
  user-spec = types.submodule {
    options = {};
  };
  spec = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        description = ''
          Enable the configuration. This adds an item to the
          set of devtools available to the flake.
        '';
      };

      models = mkOption {
        type = types.attrsOf model-spec;
        description = ''
          Holds the configuration of all the models that will be available
          to the llmlite instance.
        '';
      };

      users = mkOption {
        type = types.attrsOf user-spec;
        default = {};
        description = ''
          The users that are allowed to authenticate against this
          llm-lite instance, keyed by user name. Authentication keys
          are generated when the instance is launched and are stored
          in the tool's private configuration directory; they are not
          part of this configuration. User names are used as file names
          for the keys, so they must be file-name-safe. Authentication
          is enabled only when at least one user is defined.
        '';
      };

      port = mkOption {
        type = types.int;
        description = ''
          The port on which lite-llm will be served.
        '';
        default = 4000;
      };
    };
  };
  perSystem = _:
  let
    imports = lib.attrValues (
      lib.mapAttrs to-lite-llm top.config.development-tools.lite-llm
    );
    to-lite-llm = lite-llm-name: lite-llm: {
      imports = [ ./setup.nix ];
      config._module.args = { inherit lite-llm lite-llm-name; };
    };
  in
    { inherit imports; }
  ;

  /**
  Translate a lite-llm instance into a generic llm provider entry.
  The url points at the QEMU user-networking host alias ('10.0.2.2')
  so that clients running inside a QEMU VM can reach the instance
  running on the host machine. Clients running on the host itself
  should use '127.0.0.1' instead.
  */
  to-llm-provider = name: llm-config: {
    endpoint = {
      type = "litellm";
      url = "http://10.0.2.2:${toString llm-config.port}";
    };
  };

  llm-providers = lib.mapAttrs to-llm-provider config.development-tools.lite-llm;
in
  {
    options = {
      development-tools.lite-llm = mkOption {
        type = types.attrsOf spec;
        description = ''
          This property allows configuring instances of llm-lite. These instances
          will be added to the catalogue of tools that can be run through
          the flake.
        '';
        default = {};
      };

      perSystem = mkPerSystemOption perSystem;
    };

    config.development-tools.llm-providers = llm-providers;
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
*/
{ pkgs, lib, devtools-prelude, llm-agent-name, llm-agent, ... }:
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
  provider-model = llm-agent.provider.models.main.model;
  provider-user = llm-agent.provider.user.name;

  /**
  The script implementing the deep agent. All secrets are read
  at runtime from the environment / the shared key directory,
  so nothing here is unsuitable for the nix store.
  */
  agent-script = pkgs.writeText "agent.py" ''
    import os

    from langchain_openai import ChatOpenAI
    from langchain_core.tools import tool
    from langgraph.prebuilt import create_react_agent

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

    # --- Dummy task tools ---
    @tool
    def list_files(directory: str) -> str:
        """List the files in the given directory."""
        return "\n".join(sorted(os.listdir(directory)))

    tools = [list_files]

    # --- The deep agent, given a dummy task ---
    agent = create_react_agent(llm, tools)

    result = agent.invoke({
        "messages": [
            ("user",
             "List the files in /tmp and briefly summarize what you find.")
        ]
    })

    for message in result["messages"]:
        content = getattr(message, "content", None)
        if content:
            print(content)
  '';

  /**
  The nixpkgs evaluation used to build the guest system. The
  'pkgs' module argument of a flake-parts per-system module is
  already system specific, so re-importing nixpkgs at the same
  system yields a consistent evaluation.
  */
  nixpkgs' = import pkgs.path { system = pkgs.system; };

  /**
  The NixOS configuration of the guest VM. The agent runs as a
  systemd service; the host's private configuration directory
  (holding the provider authentication keys) is shared read-only
  through a 9p mount so that secrets never enter the nix store
  or the QEMU command line.
  */
  vm = nixpkgs'.lib.nixosSystem {
    system = pkgs.system;
    modules = [
      "${pkgs.path}/nixos/modules/virtualisation/qemu-vm.nix"
      {
        virtualisation.memorySize = 2048;
        virtualisation.cores = 2;

        # Share the host's private configuration directory with
        # the guest through 9p. The mount is read-only; the agent
        # only needs to read its authentication key.
        virtualisation.qemu.options = [
          "-virtfs local,path=/devtools-config,mount_tag=devtools-config,security_model=none,readonly=on"
        ];
        fileSystems."/run/agent-keys" = {
          device = "devtools-config";
          fsType = "9p";
          options = [ "trans=virtio" "version=9p2000.L" "ro" ];
        };

        # The agent service. Non-secret parameters are baked in;
        # the api key is read from the shared directory at runtime.
        systemd.services.llm-agent = {
          description = "LangChain deep agent";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          environment = {
            OPENAI_BASE_URL = provider-endpoint-url;
            OPENAI_MODEL = provider-model;
            AGENT_USER = provider-user;
            AGENT_KEYS_DIR = "/run/agent-keys";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            exec ${agent-python}/bin/python ${agent-script}
          '';
        };
      }
    ];
  };

  /**
  The host-side launch script. It sources the tool specific
  environment (defining DEVTOOLS_CONFIG), warns if no llm
  provider is reachable on the host, and boots the VM with
  the private configuration directory shared through 9p.
  */
  launch-llm-agent = pkgs.writeScript "launch-${llm-agent-name}" ''
    #!${pkgs.bash}/bin/bash
    set -e

    source "${devtools-prelude.get-config llm-agent-name}"

    if ! ${pkgs.curl}/bin/curl -s "${provider-endpoint-url}" >/dev/null 2>&1; then
      echo -e "\033[33mWarning: no llm provider seems to be reachable at '${provider-endpoint-url}'.\033[0m" >&2
      echo "If a lite-llm instance provides this model, launch it on the host first." >&2
    fi

    export DEVTOOLS_CONFIG
    exec ${vm.config.system.build.vm}/bin/run-${pkgs.system}-vm
  '';

in
{
  config.apps."devtools/${llm-agent-name}" = {
    type = "app";
    program = "${launch-llm-agent}";
  };
}
```

### Notes on the implementation

1. **Key sharing**: the host's `$DEVTOOLS_CONFIG` is shared read-only via 9p (`-virtfs ... readonly=on`), mounted at `/run/agent-keys` in the guest. The agent reads `users/<user>.key` at runtime — the key never enters the store or the QEMU command line. The `security_model=none` + read-only combination means the guest cannot modify host files.

2. **`DEVTOOLS_CONFIG` export**: the launch script exports it so QEMU passes it into the `-virtfs path=` flag (the flag is embedded in the guest's QEMU options, which read the variable at launch time).

3. **Agent API**: I used `langgraph.prebuilt.create_react_agent`, which is the current standard for LangChain deep agents. If your nixpkgs `langchain` version doesn't propagate `langgraph`, tell me and I'll switch to the legacy `langchain.agents` API or add `ps.langgraph` explicitly to `withPackages`.

4. **VM launcher**: `config.system.build.vm` from `qemu-vm.nix` produces a script at `bin/run-<system>-vm` that boots the VM with the right kernel/initrd/cmdline.

5. **Usage**: start LiteLLM on the host (`nix run .#devtools.prelude-lite-llm`), then `nix run .#devtools.prelude-llm-agent` — the guest boots, the service runs the dummy task through the provider, and the output lands in the guest journal (`journalctl -u llm-agent` on the guest console).

> Tokens: 12k sent, 3.4k received. Cost: $0.0057 message, $0.02 session.  
> Applied edit to lite-llm/config.nix  
> Applied edit to llm-agent/setup.nix  
> Commit 0dca3bf feat: run llm-agent in a NixOS QEMU VM with 9p key sharing  
