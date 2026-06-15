#!/usr/bin/env bash
set -euo pipefail

sandboxed_version="0.0.5"

usage() {
    cat <<'EOF'
Usage: sbxd      [--rebuild] [--just-print=config|commands] [--target <target>] <target-as-command> [command args...]
       sandboxed [--rebuild] [--just-print=config|commands] [--target <target>] <target-as-command> [command args...]


Run a target tool inside a disposable Podman or Docker container for the current directory.
Shipped sandbox targets live in the installed targets/<target>/ directory.

Examples:
  sbxd opencode
  sandboxed opencode
  sandboxed opencode -c
  sandboxed opencode --help
  sandboxed --target opencode sh

Options:
  --version               Print sandboxed version and exit.
  --target <target>       Use this sandboxed target config while running <target-as-command>.
  --just-print=config     Print the effective merged target config and exit without building or running a container.
  --just-print=commands   Print the generated build/run commands and exit without building or running a container.
EOF
}

rebuild=0
just_print_command=0
just_print_config=0
target_name=""
command_args=()
target_arg=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --version)
            printf 'sandboxed %s\n' "$sandboxed_version"
            exit 0
            ;;
        --rebuild)
            rebuild=1
            shift
            ;;
        --just-print=commands)
            just_print_command=1
            shift
            ;;
        --just-print=config)
            just_print_config=1
            shift
            ;;
        --just-print=*)
            printf 'Unsupported --just-print value: %s\n' "${1#--just-print=}" >&2
            exit 1
            ;;
        --target)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' "Missing value for --target" >&2
                exit 1
            fi
            target_name="$2"
            shift 2
            break
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$target_name" ]; then
    if [ "$#" -lt 1 ]; then
        usage >&2
        exit 1
    fi
    target_arg="$1"
    target_name="$target_arg"
    shift
    if [ "$#" -gt 0 ]; then
        command_args=("$target_arg" "$@")
    fi
else
    if [ "$#" -lt 1 ]; then
        usage >&2
        exit 1
    fi
    target_arg="$1"
    shift
    command_args=("$target_arg" "$@")
fi

case "$target_name" in
    *[!A-Za-z0-9._-]* | .* | -* | *..*)
        printf 'Invalid sandboxed target: %s\n' "$target_name" >&2
        exit 1
        ;;
esac

runtime=""
runtime_available=0
if command -v podman >/dev/null 2>&1; then
    runtime="podman"
    runtime_available=1
elif command -v docker >/dev/null 2>&1; then
    runtime="docker"
    runtime_available=1
elif [ "$just_print_command" = 1 ] || [ "$just_print_config" = 1 ]; then
    runtime="podman"
else
    printf '%s\n' "podman or docker is required but neither was found in PATH" >&2
    exit 1
fi

project_dir="$(pwd -P)"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
default_sandboxed_home="$(cd -- "$script_dir/.." && pwd -P)"

host_xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
host_xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
host_xdg_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
host_xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

container_wrk_user_home_dir="/home/wrkuser"
container_xdg_data_home="$container_wrk_user_home_dir/.local/share"
container_xdg_state_home="$container_wrk_user_home_dir/.local/state"
container_xdg_cache_home="$container_wrk_user_home_dir/.cache"
container_xdg_config_home="$container_wrk_user_home_dir/.config"

sandboxed_home_dir="${SANDBOXED_HOME:-$default_sandboxed_home}"
sandboxed_python="${SANDBOXED_PYTHON:-python3}"
sandboxed_target_dir="$sandboxed_home_dir/targets/$target_name"
sandboxed_user_target_dir="$host_xdg_config_home/sandboxed/$target_name"
sandboxed_project_target_dir="$project_dir/.sandboxed/$target_name"
config_helper="$sandboxed_home_dir/src/sandboxed-config.py"
dockerfile="$sandboxed_target_dir/Dockerfile"
install_compose_file="$sandboxed_target_dir/compose.yaml"
user_compose_file="$sandboxed_user_target_dir/compose.yaml"
project_compose_file="$sandboxed_project_target_dir/compose.yaml"
image_name="${SANDBOXED_IMAGE:-localhost/sandboxed-$runtime-$target_name:uid-$(id -u)}"
container_name="sandboxed-$target_name-$(date +%s)-$$"

if [ ! -x "$config_helper" ]; then
    printf 'Config helper not found or not executable: %s\n' "$config_helper" >&2
    exit 1
fi

config_helper_args=(
    --target "$target_name"
    --runtime "$runtime"
    --runtime-available "$runtime_available"
    --project-dir "$project_dir"
    --install-target-dir "$sandboxed_target_dir"
    --user-target-dir "$sandboxed_user_target_dir"
    --project-target-dir "$sandboxed_project_target_dir"
    --container-home "$container_wrk_user_home_dir"
    --host-xdg-data-home "$host_xdg_data_home"
    --host-xdg-state-home "$host_xdg_state_home"
    --host-xdg-cache-home "$host_xdg_cache_home"
    --host-xdg-config-home "$host_xdg_config_home"
    --container-xdg-data-home "$container_xdg_data_home"
    --container-xdg-state-home "$container_xdg_state_home"
    --container-xdg-cache-home "$container_xdg_cache_home"
    --container-xdg-config-home "$container_xdg_config_home"
)

if [ "$just_print_config" = 1 ]; then
    exec env PYTHONDONTWRITEBYTECODE=1 "$sandboxed_python" "$config_helper" "${config_helper_args[@]}"
    exit 0
fi

build_context="$sandboxed_target_dir"
build_arg_args=()
run_env_args=()
volume_args=()
config_command_args=()
symlink_scan_host_dirs=()
symlink_scan_container_dirs=()
symlink_mode="automount"
lock_checks_enabled=1
lock_paths=()
lock_suffixes=()
opencode_project_config=""
opencode_sandbox_config=""
opencode_container_project_config=""

append_volume_once() {
    local source_path="$1"
    local target_path="$2"
    local volume_arg="--volume"
    local mount_arg="$source_path:$target_path"
    local i=0

    while [ "$i" -lt "${#volume_args[@]}" ]; do
        if [ "${volume_args[$i]}" = "$volume_arg" ] && [ "${volume_args[$((i + 1))]:-}" = "$mount_arg" ]; then
            return 0
        fi
        i=$((i + 1))
    done

    volume_args+=(--volume "$mount_arg")
}

load_target_plan() {
    local kind=""
    local first=""
    local second=""
    local third=""

    while IFS=$'\t' read -r kind first second third; do
        case "$kind" in
            dockerfile)
                dockerfile="$first"
                ;;
            build_context)
                build_context="$first"
                ;;
            build_arg)
                build_arg_args+=(--build-arg "$first")
                ;;
            workdir)
                project_dir="$first"
                ;;
            env)
                run_env_args+=(--env "$first")
                ;;
            volume)
                if [ "$third" = "ro" ]; then
                    volume_args+=(--volume "$first:$second:ro")
                else
                    volume_args+=(--volume "$first:$second")
                fi
                ;;
            command_arg)
                config_command_args+=("$first")
                ;;
            symlink_mode)
                symlink_mode="$first"
                ;;
            symlink_scan)
                symlink_scan_host_dirs+=("$first")
                symlink_scan_container_dirs+=("$second")
                ;;
            lock_checks_enabled)
                if [ "$first" = "false" ]; then
                    lock_checks_enabled=0
                else
                    lock_checks_enabled=1
                fi
                ;;
            opencode_project_config)
                opencode_project_config="$first"
                opencode_sandbox_config="$second"
                opencode_container_project_config="$third"
                ;;
            lock)
                lock_paths+=("$first")
                lock_suffixes+=("$second")
                ;;
            "")
                ;;
            *)
                printf 'Unsupported target plan record: %s\n' "$kind" >&2
                exit 1
                ;;
        esac
    done < <(PYTHONDONTWRITEBYTECODE=1 "$sandboxed_python" "$config_helper" --format plan "${config_helper_args[@]}")
}

print_shell_command() {
    local separator=""
    local arg

    for arg in "$@"; do
        printf '%s%q' "$separator" "$arg"
        separator=" "
    done
    printf '\n'
}

print_shell_command_continued() {
    local separator=""
    local arg

    for arg in "$@"; do
        printf '%s%q' "$separator" "$arg"
        separator=" "
    done
    printf ' \\\n'
}

print_shell_words() {
    local separator=""
    local arg

    for arg in "$@"; do
        printf '%s%q' "$separator" "$arg"
        separator=" "
    done
}

print_command_line() {
    local prefix="$1"
    local continued="$2"
    shift 2

    printf '%s' "$prefix"
    print_shell_words "$@"
    if [ "$continued" = 1 ]; then
        printf ' \\'
    fi
    printf '\n'
}

print_command_pair_lines() {
    local prefix="$1"
    shift

    while [ "$#" -gt 0 ]; do
        print_command_line "$prefix" 1 "$1" "$2"
        shift 2
    done
}

print_build_command_pretty() {
    local command_prefix="$1"
    local option_prefix="$2"

    print_command_line "$command_prefix" 1 "$runtime" build
    print_command_line "$option_prefix" 1 --file "$dockerfile"
    print_command_line "$option_prefix" 1 --tag "$image_name"
    print_command_pair_lines "$option_prefix" "${build_arg_args[@]}"
    print_command_line "$option_prefix" 0 "$build_context"
}

print_run_command_pretty() {
    local command_prefix="$1"
    local option_prefix="$2"
    local i=0

    print_command_line "$command_prefix" 1 "$runtime" run
    print_command_line "$option_prefix" 1 --rm
    print_command_line "$option_prefix" 1 "${tty_args[@]}"
    print_command_line "$option_prefix" 1 --name "$container_name"
    print_command_line "$option_prefix" 1 --hostname "$container_name"
    if [ "$runtime" = "podman" ]; then
        print_command_line "$option_prefix" 1 --userns keep-id
    fi
    print_command_line "$option_prefix" 1 --user "$(id -u):$(id -g)"
    print_command_line "$option_prefix" 1 --cap-drop ALL
    print_command_line "$option_prefix" 1 --cap-add SETUID
    print_command_line "$option_prefix" 1 --cap-add SETGID
    print_command_line "$option_prefix" 1 --cap-add AUDIT_WRITE
    print_command_line "$option_prefix" 1 --workdir "$project_dir"
    print_command_line "$option_prefix" 1 --env "HOME=$container_wrk_user_home_dir"
    print_command_line "$option_prefix" 1 --env "XDG_DATA_HOME=$container_xdg_data_home"
    print_command_line "$option_prefix" 1 --env "XDG_STATE_HOME=$container_xdg_state_home"
    print_command_line "$option_prefix" 1 --env "XDG_CACHE_HOME=$container_xdg_cache_home"
    print_command_line "$option_prefix" 1 --env "XDG_CONFIG_HOME=$container_xdg_config_home"
    print_command_line "$option_prefix" 1 --env 'OPENCODE_CONFIG_CONTENT={"permission":"allow"}'
    print_command_pair_lines "$option_prefix" "${volume_args[@]}"
    if [ "${#effective_command_args[@]}" -eq 0 ]; then
        print_command_line "$option_prefix" 0 "$image_name"
        return 0
    fi

    print_command_line "$option_prefix" 1 "$image_name"

    while [ "$i" -lt "${#effective_command_args[@]}" ]; do
        if [ "$i" -eq "$((${#effective_command_args[@]} - 1))" ]; then
            print_command_line "$option_prefix" 0 "${effective_command_args[$i]}"
        else
            print_command_line "$option_prefix" 1 "${effective_command_args[$i]}"
        fi
        i=$((i + 1))
    done
}

print_build_block_pretty() {
    printf '(\n'
    print_build_command_pretty $'\t' $'\t\t'
    printf ')'
}

print_run_block_pretty() {
    printf '(\n'
    print_run_command_pretty $'\t' $'\t\t'
    printf ')\n'
}

print_runtime_commands_pretty() {
    if [ "$target_name" = "opencode" ]; then
        printf '# sandboxed prepares %q before %s run.\n' "$opencode_sandbox_config" "$runtime"
        printf '# That copy is mounted as %q because OPENCODE_CONFIG_CONTENT alone does not stop OpenCode from loading project opencode.json.\n\n' "$opencode_container_project_config"
    fi

    if [ "$print_build_command" = 1 ]; then
        print_build_block_pretty
        printf ' && '
    fi

    print_run_block_pretty
}

write_opencode_sandbox_config() {
    local source_config="$1"
    local target_config="$2"

    if [ ! -f "$source_config" ]; then
        printf '%s\n' '{"permission":"allow"}' > "$target_config"
        return 0
    fi

    PROJECT_OPENCODE_SOURCE="$source_config" PROJECT_OPENCODE_TARGET="$target_config" perl <<'PERL'
use strict;
use warnings;
use JSON::PP;

my $source = $ENV{PROJECT_OPENCODE_SOURCE};
my $target = $ENV{PROJECT_OPENCODE_TARGET};

open my $in, '<', $source or die "Cannot read $source: $!\n";
local $/;
my $content = <$in>;
close $in or die "Cannot close $source: $!\n";

my $config = JSON::PP->new->relaxed(1)->decode($content);
die "Expected JSON object in $source\n" unless ref($config) eq 'HASH';

$config->{permission} = 'allow';

my $tmp = "$target.tmp";
open my $out, '>', $tmp or die "Cannot write $tmp: $!\n";
print {$out} JSON::PP->new->pretty(1)->canonical(1)->encode($config);
close $out or die "Cannot close $tmp: $!\n";
rename $tmp, $target or die "Cannot rename $tmp to $target: $!\n";
PERL
}

image_exists() {
    if [ "$runtime" = "podman" ]; then
        podman image exists "$image_name"
        return $?
    fi

    docker image inspect "$image_name" >/dev/null 2>&1
}

check_locks() {
    local i=0

    if [ "$lock_checks_enabled" != 1 ]; then
        return 0
    fi

    if [ "$just_print_command" = 1 ] || ! command -v fuser >/dev/null 2>&1; then
        return 0
    fi

    while [ "$i" -lt "${#lock_paths[@]}" ]; do
        local lock_path="${lock_paths[$i]}"
        local suffixes="${lock_suffixes[$i]}"
        local lock_files=("$lock_path")
        local suffix=""

        if [ ! -f "$lock_path" ]; then
            i=$((i + 1))
            continue
        fi

        IFS=',' read -r -a suffix_array <<< "$suffixes"
        for suffix in "${suffix_array[@]}"; do
            [ -n "$suffix" ] && [ -e "$lock_path$suffix" ] && lock_files+=("$lock_path$suffix")
        done

        if fuser "${lock_files[@]}" >/dev/null 2>&1; then
            printf 'Sandboxed lock file seems to be in use: %s\n' "$lock_path"
            fuser -v "${lock_files[@]}" || true
            printf '\n%s\n' "Close the other target instance before starting sandboxed mode."
            exit 1
        fi

        i=$((i + 1))
    done
}

check_symlinks_in_mounted_dirs() {
    local found_symlinks=0
    local broken_symlinks=0
    local i=0

    while [ "$i" -lt "${#symlink_scan_host_dirs[@]}" ]; do
        local host_dir="${symlink_scan_host_dirs[$i]}"
        local container_dir="${symlink_scan_container_dirs[$i]}"

        if [ ! -d "$host_dir" ]; then
            i=$((i + 1))
            continue
        fi

        while IFS= read -r -d '' link_path; do
            local link_target
            local link_dir
            local rel_link_path
            local rel_link_dir
            local container_link_dir
            local host_target_path
            local container_target_path
            found_symlinks=1

            link_target="$(readlink "$link_path")"
            printf 'Symlink in mounted directory: %s -> %s\n' "$link_path" "$link_target" >&2

            if [ "$symlink_mode" != "automount" ]; then
                continue
            fi

            link_dir="$(dirname "$link_path")"
            rel_link_path="${link_path#"$host_dir"/}"
            rel_link_dir="$(dirname "$rel_link_path")"
            container_link_dir="$container_dir"
            if [ "$rel_link_dir" != "." ]; then
                container_link_dir="$container_dir/$rel_link_dir"
            fi

            if [ "${link_target#/}" != "$link_target" ]; then
                host_target_path="$link_target"
                container_target_path="$link_target"
            else
                host_target_path="$link_dir/$link_target"
                container_target_path="$container_link_dir/$link_target"
            fi

            if [ ! -e "$host_target_path" ]; then
                printf 'Broken symlink target on host: %s -> %s\n' "$link_path" "$host_target_path" >&2
                broken_symlinks=1
                continue
            fi

            if [ -d "$host_target_path" ]; then
                append_volume_once "$host_target_path" "$container_target_path"
            else
                append_volume_once "$(dirname "$host_target_path")" "$(dirname "$container_target_path")"
            fi
        done < <(find "$host_dir" -type l -print0)

        i=$((i + 1))
    done

    if [ "$broken_symlinks" = 1 ]; then
        printf '\nRefusing to start because at least one symlink target is missing on host.\n' >&2
        exit 1
    fi

    if [ "$found_symlinks" = 1 ] && [ "$symlink_mode" = "refuse" ]; then
        if [ "$just_print_command" = 1 ]; then
            printf '\nPrinted command will not include symlink target bind-mounts.\n' >&2
            printf 'Set x-sandboxed.symlinks.mode to automount to include them.\n' >&2
            return 0
        fi

        printf '\nRefusing to start because mounted directories contain symlinks.\n' >&2
        printf 'Set x-sandboxed.symlinks.mode to automount to bind-mount symlink targets too.\n' >&2
        exit 1
    fi
}

load_target_plan

if [ ! -f "$dockerfile" ]; then
    printf 'Dockerfile not found: %s\n' "$dockerfile" >&2
    exit 1
fi

if [ "$target_name" = "opencode" ]; then
    opencode_host_data_dir="$host_xdg_data_home/opencode"
    opencode_host_config_dir="$host_xdg_config_home/opencode"
    opencode_host_cache_dir="$host_xdg_cache_home/opencode"
    opencode_host_state_dir="$host_xdg_state_home/opencode"
    if [ -z "$opencode_project_config" ]; then
        opencode_project_config="$project_dir/opencode.json"
    fi
    if [ -z "$opencode_sandbox_config" ]; then
        opencode_sandbox_config="$project_dir/.sandboxed/opencode/opencode.json"
    fi
    if [ -z "$opencode_container_project_config" ]; then
        opencode_container_project_config="$project_dir/opencode.json"
    fi
    opencode_sandbox_config_dir="$(dirname "$opencode_sandbox_config")"

    if [ "$just_print_command" != 1 ]; then
        mkdir -p \
            "$opencode_host_data_dir" \
            "$opencode_host_config_dir" \
            "$opencode_host_cache_dir" \
            "$opencode_host_state_dir" \
            "$opencode_sandbox_config_dir" \
        ;

        # OPENCODE_CONFIG_CONTENT keeps runtime permissions open, but OpenCode
        # still loads the project's own opencode.json. Mount a modified copy so
        # project config stays available without changing the real project file.
        write_opencode_sandbox_config "$opencode_project_config" "$opencode_sandbox_config"
    fi
fi

check_locks
check_symlinks_in_mounted_dirs

build_args=(
    "$runtime" build
    --file "$dockerfile"
    --tag "$image_name"
    "${build_arg_args[@]}"
    "$build_context"
)

print_build_command=0
if [ "$just_print_command" = 1 ]; then
    if [ "$rebuild" = 1 ] || [ "$runtime_available" != 1 ] || ! image_exists; then
        print_build_command=1
    fi
elif [ "$rebuild" = 1 ] || ! image_exists; then
    "${build_args[@]}"
fi

tty_args=(--interactive)
if [ -t 0 ] && [ -t 1 ]; then
    tty_args=(--interactive --tty)
fi

effective_command_args=("${command_args[@]}")
if [ "${#effective_command_args[@]}" -eq 0 ]; then
    effective_command_args=("${config_command_args[@]}")
fi

# --security-opt no-new-privileges is good hardening, but sandboxed expects
# wrkuser to have full passwordless sudo rights inside the container.
run_args=(
    "$runtime" run
    --rm
    "${tty_args[@]}"
    --name "$container_name"
    --hostname "$container_name"
    --user "$(id -u):$(id -g)"
    --cap-drop ALL
    --cap-add SETUID
    --cap-add SETGID
    --cap-add AUDIT_WRITE
    --workdir "$project_dir"
    "${run_env_args[@]}"
    "${volume_args[@]}"
    "$image_name"
    "${effective_command_args[@]}"
)

if [ "$runtime" = "podman" ]; then
    run_args=(
        "$runtime" run
        --rm
        "${tty_args[@]}"
        --name "$container_name"
        --hostname "$container_name"
        --userns keep-id
        --user "$(id -u):$(id -g)"
        --cap-drop ALL
        --cap-add SETUID
        --cap-add SETGID
        --cap-add AUDIT_WRITE
        --workdir "$project_dir"
        "${run_env_args[@]}"
        "${volume_args[@]}"
        "$image_name"
        "${effective_command_args[@]}"
    )
fi

if [ "$just_print_command" = 1 ]; then
    print_runtime_commands_pretty
    exit 0
fi

exec "${run_args[@]}"


#--env "TERM=${TERM:-xterm-256color}" \
#--env "COLORTERM=${COLORTERM:-}" \
