# sandboxed

`sandboxed` runs command-line tools inside disposable containers while keeping the current host working directory as the main project directory. The primary use case is AI coding agents and other console clients such as `opencode`, `claude`, `gemini`, and `codex`, but the design is intentionally generic.

This repository is the standalone source tree. Repository-specific deployment glue belongs outside the core launcher unless it is packaging for `sandboxed` itself.

## Status

The current implementation is still an early launcher, but it already has the first version-zero project pieces: `sandboxed`/`sbxd`, automatic `podman` then `docker` runtime selection, `--just-print=commands`, `--just-print=config`, a PyYAML config helper, an initial `targets/opencode/compose.yaml` target config, and local `just` verification recipes.

The runtime command is built from the effective YAML target plan for build args, env, volumes, command, workdir, symlink scan, locks, and Dockerfile/build context. A small `opencode`-specific preparation step still creates the sandbox copy of `opencode.json`; that should eventually move behind a generic `x-sandboxed` mechanism.

This is a version-zero project. Do not preserve backward compatibility unless there is an explicit shipped-user requirement. Prefer the clean target interface over aliases and compatibility flags.

## Requirements

The launcher itself expects a POSIX-like environment with:

* `bash`;
* `python3` with PyYAML for `src/sandboxed-config.py`;
* `podman` or `docker` for real container execution.

The local verification recipes additionally expect `just`.

For the shipped `opencode` target, the image build uses Alpine packages and downloads OpenCode through the upstream installer, so a first build needs network access.

## Installation

Current Homebrew workflow:

```sh
brew tap Kirill-Znamenskiy/sandboxed
brew trust --tap Kirill-Znamenskiy/sandboxed
brew install sandboxed
```

After the tap is configured, the normal install command is:

```sh
brew install sandboxed
```

For development against a local checkout of `Kirill-Znamenskiy/homebrew-sandboxed`, point the tap at that checkout instead:

```sh
cd /path/to/homebrew-sandboxed
brew tap Kirill-Znamenskiy/sandboxed "$PWD"
brew trust --tap Kirill-Znamenskiy/sandboxed
brew install sandboxed
```

To pick up later changes from the tap:

```sh
brew update
brew upgrade sandboxed
```

The Homebrew formula installs launcher source under Homebrew `libexec`, installs shipped targets from `targets/`, creates both `sandboxed` and `sbxd` commands, and uses user/project config from the normal XDG/project locations.

## Core Value

The core value of `sandboxed` is zero-friction safe execution. A user should be able to enter a project, run `sandboxed <target>` or `sbxd <target>`, and start working without extra flags, one-off parameters, or manual setup for the normal path.

Configuration should be done once in YAML at the right level: shipped defaults, per-user overrides, or per-project overrides. After that, the launcher should make the correct container command automatically.

For AI agents, the goal is to make the agent session feel unrestricted inside the configured sandbox. The user should be able to tell the agent to proceed without `sandboxed` interrupting every action with extra permission questions. Safety comes from the container boundary and from explicitly controlled mounts, not from constant interactive hesitation.

The default risk model is local and bounded: the target may freely change or delete data that is mounted into the container, especially the project directory, but it should not get broad access to the host home directory, host Docker socket, SSH keys, Git credentials, or other sensitive host state unless the target config explicitly opts into that access.

Inside the container, the target user should be able to do everything the image permits, including passwordless `sudo`. The point is not to restrict the user inside the container; the point is to keep the container boundary and mounted host state explicit.

`sandboxed` should not optimize defaults for pushing to remote Git repositories. A normal workflow is that the agent edits code in the sandbox, then the user reviews and pushes from the host. Enabling Git push from inside the container should require explicit credentials or mounts in target config.

## Commands

The project should be available through two equivalent command names:

```sh
sandboxed <target-as-command> [command args...]
sbxd <target-as-command> [command args...]
```

`sbxd` is only a short alias for interactive use. Both commands should call the same launcher and have the same behavior.

The first positional argument is normally both the sandboxed target name and the command to run inside the container:

```sh
sandboxed opencode
sandboxed claude --help
sbxd codex
```

When the sandboxed target name must differ from the command, use an explicit target selector:

```sh
sandboxed --target opencode sh
```

Useful inspection commands:

```sh
sandboxed --just-print=config opencode
sandboxed --just-print=commands opencode
sandboxed --just-print=commands --target opencode sh -c 'id; pwd; opencode --version'
```

`--just-print=config` and `--just-print=commands` are safe introspection modes: they must not build images or start containers.

## Responsibility

`sandboxed` is responsible for forming and running the best available container command for the requested target. It should not try to fix product-specific behavior of the tools it launches.

Examples of responsibilities:

* choose `podman` or `docker`;
* build an image when needed;
* run a disposable container with the right working directory, user, environment, and mounts;
* merge sandbox target configuration from the supported config levels;
* reject unsafe or ambiguous mount/symlink situations when configured to do so.

Examples of non-responsibilities:

* fixing login, browser, authentication, quota, or model-selection flows of AI CLI tools;
* emulating missing features of a specific container runtime;
* silently weakening the security envelope because a target tool expects broader host access.

## Runtime Selection

The launcher should automatically select the container runtime:

1. use `podman` when it is available;
2. otherwise use `docker` when it is available;
3. otherwise fail with a clear error.

Runtime selection should not require a launch option in the normal path.

Podman should use `--userns keep-id` where possible. Docker does not have the same portable keep-id behavior, so the practical baseline is to run as the host UID/GID with `--user "$(id -u):$(id -g)"` and to build images with matching user/group build args.

Both runtimes should preserve the common security envelope where supported:

* drop Linux capabilities by default;
* run as the host user rather than as root;
* keep passwordless `sudo` usable inside the container;
* keep containers disposable by default.

## Project Directory

The default project directory is the current host working directory resolved at launcher start. This directory is mounted into the container at the same path and used as the container working directory.

Future versions may allow an explicit project directory option, but the default behavior should stay predictable: `sandboxed <target>` means "run this target for the directory I am currently in".

## Config Levels

Configuration is resolved per target from three levels. All levels use the same target directory layout.

The base installation level contains defaults shipped with the installed copy. In this source tree, and in Homebrew `libexec`, that is:

```text
<install-root>/targets/<target>/
```

In development and tests, `SANDBOXED_HOME` can override `<install-root>`.

The user level contains per-user overrides that apply to all projects:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/sandboxed/<target>/
```

The project level contains overrides for the current project directory:

```text
$PWD/.sandboxed/<target>/
```

The merge order is:

```text
<install-root>/targets/<target>/
  -> ${XDG_CONFIG_HOME:-$HOME/.config}/sandboxed/<target>/
  -> $PWD/.sandboxed/<target>/
```

Later levels override earlier levels. Project-level configuration has the highest priority.

The project-level lookup should initially be limited to the current working directory. Recursive search through parent directories can be added later as an explicit feature if needed.

## Target Layout

A target directory should contain everything needed to build and run one target tool:

```text
targets/
  <target>/
    Dockerfile
    compose.yaml
```

The planned default targets are:

```text
targets/opencode/
targets/claude/
targets/gemini/
targets/codex/
```

The directory name is the target name and should normally match the command name inside the container.

## compose.yaml

Each target should be configured with a `compose.yaml` file. This file is a declarative source for build, environment, mounts, command defaults, and sandbox-specific options. The launcher may parse it and translate the effective result into direct `podman` or `docker` commands; it does not have to run `docker compose` or `podman-compose` directly.

The config should use a normal Compose-like structure for familiar concepts and `x-sandboxed` for launcher-specific behavior.

Example shape:

```yaml
services:
  sandboxed:
    build:
      context: .
      dockerfile: Dockerfile
    command: ["opencode"]
    environment:
      XDG_DATA_HOME: /home/wrkuser/.local/share
      XDG_STATE_HOME: /home/wrkuser/.local/state
      XDG_CACHE_HOME: /home/wrkuser/.cache
      XDG_CONFIG_HOME: /home/wrkuser/.config
    volumes:
      - type: bind
        source: ${SANDBOXED_PROJECT_DIR}
        target: ${SANDBOXED_PROJECT_DIR}

x-sandboxed:
  symlinks:
    mode: automount
```

The service name can stay generic, such as `sandboxed`, because the target directory already identifies the target tool.

## Merge Semantics

The effective target config is built by merging files from the three config levels.

Planned rules:

* maps are merged recursively;
* scalar values are replaced by the later level;
* lists are replaced by default unless a specific append/prepend convention is introduced;
* unsupported keys should fail clearly rather than be ignored silently when they affect runtime behavior;
* `Dockerfile` is not merged line-by-line; the highest-priority existing `Dockerfile` is used as the build file.

This keeps overrides predictable and avoids inventing a second Compose format too early.

## Symlinks

Mounted directories may contain symlinks that point outside the mounted tree. By default the launcher should automatically bind-mount discovered symlink targets so the container sees the same paths the host user expects.

The sandbox-specific config is:

```yaml
x-sandboxed:
  symlinks:
    mode: automount # automount | refuse | ignore
```

`automount` additionally bind-mounts symlink targets and is the default. `refuse` reports symlinks and exits. `ignore` leaves symlinks as-is and is intended only for cases where broken links inside the container are acceptable.

The target config owns this policy. Do not add launch flags for symlink behavior unless there is a concrete new need that cannot be expressed in target config.

## Verification

This project has local `JustFile` recipes for repeatable checks:

```sh
just check
```

`just check` is the default quick check. It must remain safe: no image build, no container start, and no network access. It validates shell syntax, Python/YAML parsing, effective `opencode` config through `--just-print=config`, and generated runtime command through `--just-print=commands`.

Focused inspection recipes:

```sh
just print-config-opencode
just print-command-opencode
```

Use them when changing target config merging, mounts, XDG paths, runtime flags, symlink policy, lock checks, or `targets/opencode/compose.yaml`.

Runtime smoke check:

```sh
just smoke-opencode-env
```

This recipe may build an image and start disposable containers. It uses a temporary project-level override to avoid the owner's live OpenCode data, locks, and symlink scans. The smoke has two parts:

* shell/environment smoke: checks user identity, working directory, container `HOME`/XDG paths, `opencode --version`, and passwordless `sudo`;
* direct OpenCode smoke: runs `opencode debug config` and validates that OpenCode can start non-interactively.

The default smoke intentionally does not run `opencode run` with an LLM prompt, because that depends on provider auth, quotas, model availability, and network state rather than only the sandbox launcher.

## Safety

Building images and starting containers can create local state, use the network, and execute code from Dockerfiles. Run those checks deliberately. In this infra repository they must not be run automatically without explicit owner confirmation.

Safe development checks include reading files, inspecting generated commands, validating shell syntax, and printing the effective config.
