# Roadmap

This document is the implementation roadmap for evolving `sandboxed` as a small standalone project. It is written as a handoff document: another context should be able to continue work by reading `README.md`, `AGENTS.md`, and this file.

This repository is now the source tree for `sandboxed` itself. Keep launcher code in `src/`, shipped targets in `targets/<target>/`, and project-local runtime overrides in `$PWD/.sandboxed/<target>/`.

## North Star

`sandboxed` should make this workflow reliable:

```sh
sandboxed opencode
sbxd claude
sandboxed codex --help
```

The command should run the requested console tool inside a disposable container for the current host working directory, using a target config that can be customized at install, user, and project levels.

The launcher should be generic. AI agents are the first important use case, not the only supported use case.

This is version-zero work. Optimize for the clean target architecture, not backward compatibility with temporary flags or early implementation details.

## Product Value

The product value is zero-setup safe autonomy. Once defaults, user overrides, or project overrides are configured, the normal user action should be only:

```sh
sandboxed <target>
```

or:

```sh
sbxd <target>
```

No extra flags should be required for the happy path. Configuration belongs in YAML and should be reusable across projects, users, and installed defaults.

For AI agent targets, the sandbox should provide a broad working area inside the configured boundary. The agent should be able to edit files, run commands, install dependencies inside the container when the image/config allows it, and generally proceed without `sandboxed` asking per-action permission questions.

Inside the container, the target user should be powerful. Passwordless `sudo` is expected. Runtime hardening must not break normal inner-container development just to create a false sense of safety.

The safety tradeoff is intentional: mounted data can be modified or deleted by the target, but unmounted host state should remain outside the target's reach. Host-wide escape hatches such as the Docker socket, SSH keys, Git credentials, cloud credentials, and broad home-directory mounts must be explicit config choices, not defaults.

Remote Git push is not a default success criterion. The preferred default workflow is that the target edits inside the sandbox, then the user reviews and pushes from the host. Pushing from inside the container may be supported by explicit target config, but should not drive the default mount set.

## Non-Goals

Do not make `sandboxed` responsible for target-tool product behavior.

Out of scope:

* fixing authentication, login, browser, quota, model, or update behavior of `opencode`, `claude`, `gemini`, `codex`, or other CLIs;
* hiding real differences between `podman` and `docker` when a portable equivalent does not exist;
* making remote Git push work by default through automatic credential mounts;
* weakening the container security envelope from project-local config;
* turning this infra repository into the long-term project structure.

## Invariants

Preserve these throughout all phases:

* `sandboxed` and `sbxd` are thin entry points into one implementation;
* `sandboxed <target>` works without extra flags for the normal path after the relevant target config exists;
* reusable behavior is expressed in YAML, not repeated as one-off CLI flags;
* default project directory is the current host working directory;
* default runtime preference is `podman`, then `docker`;
* container runs as the host UID/GID where possible;
* containers are disposable by default;
* capabilities are dropped by default where supported;
* passwordless `sudo` remains usable inside the container;
* sensitive host integrations are opt-in, including Docker socket, SSH keys, Git credentials, cloud credentials, and broad home mounts;
* all command construction uses arrays or equivalent safe argument handling, never string `eval`;
* no `podman build`, `podman run`, `docker build`, or `docker run` is executed in this repository without explicit owner confirmation.

## Terms

`target` is the sandbox target name, usually matching the command name, for example `opencode`, `claude`, `gemini`, or `codex`.

`project_dir` is the host working directory captured when the launcher starts.

`install level` is `<install-root>/targets/<target>/`; in development and tests, `SANDBOXED_HOME` overrides `<install-root>`.

`user level` is `${XDG_CONFIG_HOME:-$HOME/.config}/sandboxed/<target>/`.

`project level` is `$PWD/.sandboxed/<target>/`.

`effective target config` is the merged result of install, user, and project levels.

## Target Architecture

The mature launcher has these layers:

* CLI parser: handles `sandboxed`, `sbxd`, minimal diagnostic flags, target, and command args;
* runtime selector: picks `podman` or `docker` automatically;
* config resolver: finds target files at all supported levels;
* config merger: creates the effective target config from `compose.yaml` and sandbox-specific extensions;
* command builder: turns the effective target config into `build` and `run` command argv arrays;
* safety checks: validates mounts, symlinks, target names, runtime support, and lock checks;
* executor: runs commands only after all validation and only in non-print modes.

Keep these layers conceptually separate even if early implementation still lives in one script.

## Phase 0: Project Framing

Goal: make the future project understandable before changing behavior.

Work:

* add `README.md` describing the intended project model;
* add local `AGENTS.md` for work inside `.sandboxed`;
* add this `ROADMAP.md`;
* clearly mark planned behavior versus implemented behavior.

Acceptance criteria:

* a new context can identify this repository as the current source of truth;
* docs explain the three config levels and runtime selection direction;
* docs warn not to run container build/run commands without owner confirmation.

Status: done.

## Phase 1: CLI Surface and Introspection

Goal: make the public interface and safe inspection modes stable before deeper refactoring.

Work:

* add `~/.local/bin/sbxd` as the short alias stub;
* update the macOS and server base scripts to install the `sbxd` symlink next to `sandboxed`;
* extend usage text to document `sandboxed`, `sbxd`, `--target`, and minimal diagnostic flags;
* add `--just-print=commands` to print the final build/run commands without executing them;
* add `--just-print=config` as a placeholder or minimal current-state dump if full config merge is not ready;
* keep current `sandboxed opencode` behavior working.

Acceptance criteria:

* `sandboxed --help` documents both command names;
* `sbxd` calls the same launcher as `sandboxed`;
* print modes do not call `podman` or `docker` build/run;
* existing `opencode` target can still be launched the old way when execution is explicitly allowed.

Status: done. `sbxd`, `--just-print=commands`, and `--just-print=config` are implemented.

Recommended files:

* `hosts/ANY/home/kz/.local/bin/sbxd`;
* `src/sandboxed.sh`;
* `hosts/ANY-MBP/scripts/base/base.zsh`;
* `hosts/ANY-SERV/scripts/base/base.zsh`.

## Phase 2: Runtime Abstraction

Goal: support both `podman` and `docker` without duplicating launcher logic.

Work:

* implement runtime selection: `podman` first, then `docker`;
* split build command construction from run command construction;
* preserve Podman keep-id mapping while using stable internal image user IDs;
* use `--user "$(id -u):$(id -g)"` and matching build args for Docker as the practical portable baseline;
* keep common flags such as `--rm`, `--interactive`, `--tty`, and `--cap-drop ALL` while preserving passwordless `sudo` inside the container;
* ensure image naming does not collide across target, runtime, and UID.

Acceptance criteria:

* missing runtimes produce a clear error;
* automatic runtime selection chooses `podman` before `docker`;
* `--just-print=commands <target>` prints the selected runtime argv without build/run execution;
* no runtime-specific branch silently drops the security envelope.

Status: mostly done. Runtime selection is automatic and command construction supports Podman and Docker. A public runtime override is intentionally not part of the version-zero CLI.

Implementation guidance:

* keep runtime-specific differences in small functions;
* never build shell command strings for execution;
* printing commands must shell-quote arguments for readability, but execution must use argv arrays.

## Phase 3: Target Spec and Default Targets

Goal: introduce the target layout while preserving the current working target.

Work:

* add `compose.yaml` to `targets/opencode/` as the first real declarative target config;
* represent current `opencode` build context, command, XDG mounts, env, and symlink policy in the target config as far as the current parser can support;
* add initial target directories for `claude`, `gemini`, and `codex` only when their commands and install method are confirmed;
* keep each default target minimal and generic;
* avoid embedding private credentials or host-specific secrets in default targets.

Acceptance criteria:

* `targets/opencode/compose.yaml` documents the same intent as the current hardcoded logic;
* skeleton targets do not pretend to be fully tested if they are only templates;
* target files are useful both in this repo and after future standalone extraction.

Status: partially done. `targets/opencode/compose.yaml` exists as the first target config seed. Other default targets are still pending.

Recommended target names:

* `opencode` for `opencode`;
* `claude` for `claude`;
* `gemini` for `gemini`;
* `codex` for `codex`.

## Phase 4: Config Engine

Goal: implement real three-level target resolution and merge.

Work:

* resolve target directories from install, user, and project levels;
* load `compose.yaml` from each level when present;
* merge configs in the documented order;
* choose the highest-priority existing `Dockerfile` rather than attempting line-level Dockerfile merge;
* expose the effective result through `--just-print=config`;
* fail clearly on unsupported runtime-affecting keys instead of silently ignoring them.

Critical decision:

* do not parse YAML with ad-hoc bash logic;
* either introduce a small helper for YAML handling or require a well-defined external YAML tool;
* document the dependency before relying on it.

Recommended direction:

* keep the shell entry point thin;
* move config loading and merging into a small helper once real YAML merge is required;
* prefer correctness and predictable errors over accepting every Compose feature.

Acceptance criteria:

* install-only config works;
* user-level config can override install-level config;
* project-level config can override user-level config;
* `--just-print=config` shows which files participated in the merge;
* project-level lookup is limited to `$PWD/.sandboxed/<target>/` unless parent discovery is explicitly added later.

Status: done for the current supported subset. `src/sandboxed-config.py` loads and recursively merges install, user, and project `compose.yaml` files with PyYAML and exposes the result through `--just-print=config`.

Merge rules:

* maps merge recursively;
* scalars replace earlier values;
* lists replace earlier values by default;
* append/prepend list semantics require an explicit future convention;
* `x-sandboxed` is the namespace for launcher-specific behavior.

## Phase 5: Command Builder From Effective Config

Goal: make the effective config the source of runtime command construction.

Work:

* map service build config to `podman build` or `docker build`;
* map service run config to `podman run` or `docker run`;
* support environment, workdir, command, entrypoint when needed, bind mounts, and build args;
* keep security-critical runtime options controlled by the launcher rather than project-local config;
* make `${SANDBOXED_PROJECT_DIR}` and XDG placeholders explicit and deterministic;
* preserve current symlink scanning behavior through `x-sandboxed.symlinks.mode`.

Acceptance criteria:

* generated command for `opencode` is behaviorally equivalent to current direct logic;
* Docker and Podman command generation share the same effective config;
* `--just-print=commands` can be used as a safe review step before execution;
* unsupported config keys produce actionable errors.

Status: mostly done for the current supported subset. The launcher consumes the effective YAML plan for build args, env, volumes, command, workdir, symlink scan, locks, and Dockerfile/build context. The remaining work is broadening validation and reducing target-specific preparation hooks.

## Phase 6: Migrate Hardcoded Tool Logic

Goal: remove target-specific branches from the launcher where configuration can express the behavior.

Work:

* move `opencode` XDG mount declarations into `targets/opencode/compose.yaml` or `x-sandboxed` config;
* keep only generic mount expansion logic in the launcher;
* express symlink scan directories declaratively;
* decide whether lock checks such as `opencode.db` belong in a generic `x-sandboxed.locks` mechanism or remain a small special case until justified;
* avoid adding tool-specific hacks for new AI CLIs without first checking whether target config can express the need.

Acceptance criteria:

* adding a new basic CLI target does not require editing the main launcher;
* `opencode` remains a target, not a hardcoded mode;
* any remaining special cases are explicitly documented with a removal path.

Status: partially done. `opencode` XDG mounts, env, command, locks, symlink scan, and project config paths are represented in `targets/opencode/compose.yaml`. A small hardcoded preparation step still writes the sandbox `opencode.json` copy.

## Phase 7: Test and Validation Harness

Goal: make future changes safe without requiring real container execution.

Work:

* add tests around CLI parsing and target resolution;
* add tests around runtime selection with fake `podman` and `docker` binaries in `PATH`;
* add tests around generated argv for Podman and Docker;
* add fixtures for install, user, and project config merge;
* add tests for symlink automount, refuse, and ignore modes using temporary directories;
* keep real build/run tests manual unless the owner explicitly enables them.

Acceptance criteria:

* normal verification does not build images or start containers;
* tests can run on a host without Podman or Docker by using fake runtime commands;
* a change that weakens default security flags fails tests;
* a change that breaks three-level config precedence fails tests.

## Phase 8: Standalone Extraction Readiness

Goal: make the project easy to move out of this infra repository.

Work:

* define standalone repository layout;
* separate project files from this repo's host installation glue;
* add Homebrew packaging that installs source files under `libexec`, target files from `targets/`, and exposes `sandboxed`/`sbxd` in `bin`;
* keep this repo's `hosts/ANY` copy as an installed/vendor-like copy until the owner chooses a new source of truth;
* decide whether this repo should later consume the standalone project by copy, submodule, package, or install script.

Acceptance criteria:

* project logic can be copied to a standalone repo without bringing unrelated host configs;
* host-specific deployment remains outside the standalone core;
* README is suitable as the seed of the standalone project README.

## Parallel Workstreams

These can be done in separate contexts with low conflict risk if the phase boundaries are respected:

* documentation and target spec: `README.md`, `ROADMAP.md`, target `compose.yaml` files;
* CLI alias and install glue: `.local/bin/*`, `ANY-MBP/scripts/base/base.zsh`, `ANY-SERV/scripts/base/base.zsh`;
* runtime command builder: `src/sandboxed.sh` runtime functions and print modes;
* config engine: helper script and config fixtures;
* default AI targets: `opencode`, `claude`, `gemini`, `codex` directories.

Avoid running two contexts against `src/sandboxed.sh` at the same time unless each context has a narrow, non-overlapping section.

## Recommended Next Step

Continue with Phase 6 and Phase 7.

Reasoning:

* `sbxd`, runtime selection, config introspection, and YAML-backed command construction are already implemented;
* hardcoded `opencode` preparation should move behind generic `x-sandboxed` handling;
* the next safety step is adding tests around fake runtimes and config merge fixtures;
* this directly supports the zero-flags, project-configured target workflow.

## Handoff Checklist

Before making changes in a new context:

* read `AGENTS.md`;
* read `README.md`;
* read this roadmap;
* inspect current `git status --short` and relevant diffs;
* do not run container build/run commands without explicit confirmation;
* prefer `--just-print=commands`, `--just-print=config`, static shell checks, and diffs for verification.

After making changes:

* update this roadmap if phase status or architectural decisions changed;
* keep README aligned with user-facing behavior;
* keep AGENTS aligned with contributor rules;
* report which checks were run and which runtime checks were intentionally not run.

## Open Decisions

These should be resolved before or during the phase where they first matter:

* whether default AI targets install latest CLI versions or pin versions;
* which host state directories each AI target should mount by default;
* whether project config may ever opt into broader privileges, and how explicit that opt-in must be;
* whether parent-directory project config discovery is worth adding after the initial `$PWD` model.
