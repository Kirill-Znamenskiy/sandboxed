# AGENTS.md

## Scope

This repository is the standalone source tree for the `sandboxed` project. Treat host-specific deployment glue as outside the core project unless there is a concrete packaging reason to keep it here.

Keep implementation generic. Do not couple `sandboxed` to unrelated details of this infra repository unless there is a concrete deployment reason.

This is version-zero work. Do not add backward-compatibility aliases or compatibility branches unless the owner explicitly asks for them.

Use GitFlow-style branching:

- `main` is release-only. Do not commit ordinary development fixes directly to `main`.
- `dev` is the integration branch for ongoing work.
- New product changes should happen on named feature branches from `dev`.
- Release preparation happens on named release branches from `dev`, such as `release/v0.0.4`.
- Release branches collect one or more feature branches with `--no-ff`; do not fast-forward GitFlow merges.
- Version bumps belong on release branches, after the intended feature merges are collected and before merging to `main`.
- Merge release branches back to `dev` with `--no-ff` so the integration branch receives the exact released state.
- Merge release branches to `main` only for a deliberate release/stable checkpoint, also with `--no-ff`.

Keep the repository root sparse:

- `src/` contains the launcher source code and helper scripts.
- `targets/<target>/` contains shipped target-specific files such as `compose.yaml` and `Dockerfile`.
- `homebrew/` is an ignored local checkout of the separate `homebrew-sandboxed` tap repository when needed for packaging work.
- `$PWD/.sandboxed/<target>/` remains project-local runtime config, not shipped target source.

## Project Goal

`sandboxed` launches command-line tools inside disposable containers for the current host working directory. The main initial audience is AI agent CLIs such as `opencode`, `claude`, `gemini`, and `codex`, but the launcher should work for arbitrary console tools.

The launcher owns container command construction and target config merging. It does not own fixing behavior of the target tools themselves.

The key product value is zero-setup safe autonomy: after target config exists, the normal path should be `sandboxed <target>` or `sbxd <target>` with no extra flags. Reusable behavior belongs in YAML at install, user, or project level.

For AI agents, prefer giving the target broad freedom inside the configured sandbox over adding per-action prompts in `sandboxed`. Safety should come from the container boundary and explicit mounts. Do not mount sensitive host state by default, including Docker socket, SSH keys, Git credentials, cloud credentials, or broad home directories.

Do not restrict the container user just to look safer. The target should be able to use passwordless `sudo` and do normal development work inside the container. Avoid runtime hardening such as `no-new-privileges` when it breaks that inner-container freedom.

Do not optimize defaults around remote Git push from inside the container. Treat pushing as a host-side review action unless target config explicitly provides the required credentials or mounts.

## Interface

The intended public commands are `sandboxed` and `sbxd`. `sbxd` is only a short alias and should call the same launcher.

The normal form is `sandboxed <target> [args...]`, where the target usually matches the command inside the container. Keep support for an explicit target selector, such as `sandboxed --target opencode sh`, when the target and command differ.

## Config Model

Targets are resolved from three levels, in this order:

1. `<install-root>/targets/<target>/`
2. `${XDG_CONFIG_HOME:-$HOME/.config}/sandboxed/<target>/`
3. `$PWD/.sandboxed/<target>/`

The install root is the directory installed by the package manager; in development and tests it may be overridden with `SANDBOXED_HOME`. All levels use the same target layout. Later levels override earlier levels. The project level is the current working directory only unless a later explicit feature adds parent-directory discovery.

Prefer `compose.yaml` as the declarative target config. The launcher may parse it and translate it into direct `podman` or `docker` commands; it does not need to use Compose as the runtime.

Use `x-sandboxed` for launcher-specific options that are not native Compose concepts.

The current config helper is `src/sandboxed-config.py` and requires `python3` with PyYAML. Keep YAML handling there; do not add ad-hoc YAML parsing in bash.

Homebrew should install `sandboxed` so the normal command is exactly `brew install sandboxed` after the tap is configured. The formula lives in the separate `Kirill-Znamenskiy/homebrew-sandboxed` tap repository, should keep source files under Homebrew `libexec`, install shipped targets from `targets/`, and expose both `sandboxed` and `sbxd` commands.

## Runtime

The intended runtime selection is `podman` when available, otherwise `docker`. Do not add a public launch option for runtime selection unless there is a concrete need.

Preserve the outer sandbox boundary by default: host UID/GID, explicit mounts, dropped capabilities where compatible with inner-container `sudo`, and disposable containers. Do not silently broaden host access from project-level config.

Symlink behavior is configured only through `x-sandboxed.symlinks.mode`; do not add CLI flags for it. Supported modes are `automount`, `refuse`, and `ignore`. The default is `automount`, which automatically adds bind-mounts for discovered symlink targets.

## Safety

Do not run `podman build`, `podman run`, `docker build`, or `docker run` without explicit owner confirmation. These operations can execute Dockerfiles, use the network, and create local container state.

Safe checks include reading files, static shell validation, diff inspection, and printing generated configs or commands.

Use `--just-print=config` and `--just-print=commands` for safe launcher verification. These modes must not build images or start containers.

## Verification

Keep local verification recipes in `JustFile` in this directory. The default quick check is:

```sh
just check
```

Run `just check` after every change in `sandboxed`. It must stay safe: no image build, no container start, no network. It should cover shell syntax, Python/YAML parsing, effective `opencode` config through `--just-print=config`, and generated runtime command through `--just-print=commands`.

When changing target config resolution, merge behavior, XDG paths, mounts, command args, symlink policy, lock checks, runtime flags, or `targets/opencode/compose.yaml`, also inspect the focused outputs:

```sh
just print-config-opencode
just print-command-opencode
```

Check that `print-config-opencode` shows the expected install/user/project levels, effective `Dockerfile`, environment, volumes, command, `x-sandboxed.symlinks`, and locks. Check that `print-command-opencode` preserves the sandbox boundary: disposable container, host UID/GID, explicit mounts only, dropped capabilities, required sudo-compatible capability adds, correct workdir, and no `--security-opt no-new-privileges`.

Real runtime smoke checks are not the default. Run them only with explicit owner confirmation, or when the owner asks to verify actual container startup, because they may build an image and start Podman/Docker containers:

```sh
just smoke-opencode-env
```

Use a real smoke check after changes to `Dockerfile`, runtime build/run execution, image naming, user/group setup, installed target binaries, passwordless sudo, or when claiming that `sandboxed opencode` actually starts. The smoke should include two launches: a shell/environment launch and a direct `opencode` CLI launch. The shell output should confirm at least: `sandboxed-smoke=ok`, expected user identity, expected working directory, container `HOME`/XDG paths, `opencode` is available and reports a version, and `sudo -n true` succeeds. The direct OpenCode launch should use a non-interactive diagnostic command such as `opencode debug config`; do not make the default smoke depend on LLM providers, auth, quotas, or model availability.

The `smoke-opencode-env` recipe should use a temporary project directory with a project-level target override that removes host OpenCode XDG mounts, lock checks, and symlink scans. This keeps the smoke runnable while a host OpenCode session is active and avoids coupling the smoke result to the owner's live OpenCode config. Use `print-command-opencode` or a manual launch to inspect the full normal command with real host mounts.

For shell-based smoke commands, prefer `sh -c` over `sh -lc`: Alpine login shell startup can reset `PATH` and hide image-level paths such as `/home/wrkuser/.opencode/bin` even when the Dockerfile `ENV PATH` is correct.

Do not wrap real runtime smoke checks with temporary `HOME` or `XDG_*` values unless the effect on the container runtime is intentional. In particular, temporary `XDG_DATA_HOME` can make rootless Podman create container storage under `/tmp`, which may leave user-namespace files that normal `rm` cannot remove. Use a temporary project directory for smoke checks, but let Podman/Docker use the user's normal runtime/storage locations.

Before commits from the infra repository root, still run the root project check:

```sh
just check
```

Do not replace the safe checks with real smoke checks. Treat runtime smoke as an additional confidence step for runtime-affecting changes, not as an every-change requirement.

## Style

Keep shell changes small and predictable. Preserve the existing `bash` style unless there is a clear reason to change it.

Document target architecture in `README.md`, and clearly distinguish planned behavior from behavior that is already implemented.
