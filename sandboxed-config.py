#!/usr/bin/env python3
import argparse
import os
import sys
from copy import deepcopy

import yaml


def merge_values(base, override):
    if isinstance(base, dict) and isinstance(override, dict):
        result = deepcopy(base)
        for key, value in override.items():
            if key in result:
                result[key] = merge_values(result[key], value)
            else:
                result[key] = deepcopy(value)
        return result

    return deepcopy(override)


def load_yaml(path):
    with open(path, "r", encoding="utf-8") as stream:
        data = yaml.safe_load(stream)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Expected YAML mapping in {path}")
    return data


def expand_string(value, variables):
    result = value
    for key, replacement in variables.items():
        result = result.replace("${" + key + "}", replacement)
    return result


def expand_values(value, variables):
    if isinstance(value, dict):
        return {key: expand_values(item, variables) for key, item in value.items()}
    if isinstance(value, list):
        return [expand_values(item, variables) for item in value]
    if isinstance(value, str):
        return expand_string(value, variables)
    return value


def existing_file(path):
    return path if os.path.isfile(path) else None


def emit_record(*items):
    print("\t".join(str(item) for item in items))


def normalize_environment(environment):
    if environment is None:
        return {}
    if isinstance(environment, dict):
        return environment
    if isinstance(environment, list):
        result = {}
        for item in environment:
            if not isinstance(item, str) or "=" not in item:
                raise ValueError(f"Unsupported environment item: {item!r}")
            key, value = item.split("=", 1)
            result[key] = value
        return result
    raise ValueError("services.sandboxed.environment must be a mapping or list")


def normalize_command(command):
    if command is None:
        return []
    if isinstance(command, str):
        return [command]
    if isinstance(command, list) and all(isinstance(item, str) for item in command):
        return command
    raise ValueError("services.sandboxed.command must be a string or string list")


def normalize_volumes(volumes):
    if volumes is None:
        return []
    if not isinstance(volumes, list):
        raise ValueError("services.sandboxed.volumes must be a list")

    result = []
    for item in volumes:
        if isinstance(item, str):
            parts = item.split(":")
            if len(parts) not in (2, 3):
                raise ValueError(f"Unsupported volume string: {item!r}")
            source, target = parts[0], parts[1]
            readonly = len(parts) == 3 and parts[2] in ("ro", "readonly")
            result.append((source, target, readonly))
            continue

        if isinstance(item, dict):
            if item.get("type", "bind") != "bind":
                raise ValueError(f"Only bind volumes are supported: {item!r}")
            source = item.get("source")
            target = item.get("target")
            if not source or not target:
                raise ValueError(f"Bind volume requires source and target: {item!r}")
            result.append((source, target, bool(item.get("read_only", False))))
            continue

        raise ValueError(f"Unsupported volume item: {item!r}")

    return result


def resolve_path(base_dir, value):
    if not value or os.path.isabs(value):
        return value
    return os.path.normpath(os.path.join(base_dir, value))


def emit_plan(result):
    compose = result["compose"]
    services = compose.get("services", {})
    service = services.get("sandboxed", {})
    if not service:
        raise ValueError("Effective target config must define services.sandboxed")
    if not isinstance(service, dict):
        raise ValueError("services.sandboxed must be a mapping")

    build = service.get("build", {})
    if isinstance(build, str):
        build = {"context": build}
    if not isinstance(build, dict):
        raise ValueError("services.sandboxed.build must be a mapping or string")

    dockerfile = result["dockerfile"]
    dockerfile_dir = os.path.dirname(dockerfile) if dockerfile else result["levels"][0]["target_dir"]
    build_context = resolve_path(dockerfile_dir, build.get("context", "."))
    build_dockerfile = dockerfile or os.path.join(build_context, build.get("dockerfile", "Dockerfile"))

    emit_record("dockerfile", build_dockerfile)
    emit_record("build_context", build_context)

    build_args = build.get("args", {})
    if isinstance(build_args, list):
        build_args = {item: "" for item in build_args}
    if not isinstance(build_args, dict):
        raise ValueError("services.sandboxed.build.args must be a mapping or list")
    for key, value in build_args.items():
        emit_record("build_arg", f"{key}={value}")

    working_dir = service.get("working_dir", result["project_dir"])
    emit_record("workdir", working_dir)

    for key, value in normalize_environment(service.get("environment")).items():
        emit_record("env", f"{key}={value}")

    for source, target, readonly in normalize_volumes(service.get("volumes")):
        emit_record("volume", source, target, "ro" if readonly else "rw")

    for item in normalize_command(service.get("command")):
        emit_record("command_arg", item)

    sandboxed = compose.get("x-sandboxed", {})
    if sandboxed is None:
        sandboxed = {}
    if not isinstance(sandboxed, dict):
        raise ValueError("x-sandboxed must be a mapping")

    symlinks = sandboxed.get("symlinks", {}) or {}
    if not isinstance(symlinks, dict):
        raise ValueError("x-sandboxed.symlinks must be a mapping")
    symlink_mode = symlinks.get("mode", "automount")
    if symlink_mode not in ("refuse", "automount", "ignore"):
        raise ValueError("x-sandboxed.symlinks.mode must be one of: refuse, automount, ignore")
    emit_record("symlink_mode", symlink_mode)
    for item in symlinks.get("scan", []) or []:
        if not isinstance(item, dict) or not item.get("host") or not item.get("container"):
            raise ValueError(f"Invalid symlink scan item: {item!r}")
        emit_record("symlink_scan", item["host"], item["container"])

    opencode = sandboxed.get("opencode", {}) or {}
    project_config = opencode.get("project_config", {}) or {}
    if project_config:
        emit_record(
            "opencode_project_config",
            project_config.get("source", ""),
            project_config.get("sandbox_copy", ""),
            project_config.get("container_target", ""),
        )

    for lock in sandboxed.get("locks", []) or []:
        if not isinstance(lock, dict) or not lock.get("path"):
            raise ValueError(f"Invalid lock item: {lock!r}")
        suffixes = lock.get("related_suffixes", []) or []
        emit_record("lock", lock["path"], ",".join(str(suffix) for suffix in suffixes))


def main():
    parser = argparse.ArgumentParser(description="Resolve sandboxed target config")
    parser.add_argument("--format", choices=("config", "plan"), default="config")
    parser.add_argument("--target", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--runtime-available", required=True)
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--install-target-dir", required=True)
    parser.add_argument("--user-target-dir", required=True)
    parser.add_argument("--project-target-dir", required=True)
    parser.add_argument("--container-home", required=True)
    parser.add_argument("--host-xdg-data-home", required=True)
    parser.add_argument("--host-xdg-state-home", required=True)
    parser.add_argument("--host-xdg-cache-home", required=True)
    parser.add_argument("--host-xdg-config-home", required=True)
    parser.add_argument("--container-xdg-data-home", required=True)
    parser.add_argument("--container-xdg-state-home", required=True)
    parser.add_argument("--container-xdg-cache-home", required=True)
    parser.add_argument("--container-xdg-config-home", required=True)
    args = parser.parse_args()

    levels = [
        ("install", args.install_target_dir),
        ("user", args.user_target_dir),
        ("project", args.project_target_dir),
    ]

    variables = {
        "SANDBOXED_TARGET": args.target,
        "SANDBOXED_RUNTIME": args.runtime,
        "SANDBOXED_PROJECT_DIR": args.project_dir,
        "SANDBOXED_CONTAINER_HOME": args.container_home,
        "SANDBOXED_HOST_UID": str(os.getuid()),
        "SANDBOXED_HOST_GID": str(os.getgid()),
        "SANDBOXED_HOST_XDG_DATA_HOME": args.host_xdg_data_home,
        "SANDBOXED_HOST_XDG_STATE_HOME": args.host_xdg_state_home,
        "SANDBOXED_HOST_XDG_CACHE_HOME": args.host_xdg_cache_home,
        "SANDBOXED_HOST_XDG_CONFIG_HOME": args.host_xdg_config_home,
        "SANDBOXED_CONTAINER_XDG_DATA_HOME": args.container_xdg_data_home,
        "SANDBOXED_CONTAINER_XDG_STATE_HOME": args.container_xdg_state_home,
        "SANDBOXED_CONTAINER_XDG_CACHE_HOME": args.container_xdg_cache_home,
        "SANDBOXED_CONTAINER_XDG_CONFIG_HOME": args.container_xdg_config_home,
    }

    compose = {}
    source_report = []
    dockerfile = None
    for name, directory in levels:
        compose_file = os.path.join(directory, "compose.yaml")
        compose_exists = os.path.isfile(compose_file)
        if compose_exists:
            compose = merge_values(compose, load_yaml(compose_file))

        level_dockerfile = existing_file(os.path.join(directory, "Dockerfile"))
        if level_dockerfile is not None:
            dockerfile = level_dockerfile

        source_report.append(
            {
                "name": name,
                "target_dir": directory,
                "compose_file": compose_file,
                "compose_exists": compose_exists,
                "dockerfile": level_dockerfile,
            }
        )

    result = {
        "target": args.target,
        "runtime": args.runtime,
        "runtime_available": args.runtime_available == "1",
        "project_dir": args.project_dir,
        "dockerfile": dockerfile,
        "levels": source_report,
        "variables": variables,
        "compose": expand_values(compose, variables),
    }

    if args.format == "plan":
        emit_plan(result)
        return

    yaml.safe_dump(result, sys.stdout, sort_keys=False)


if __name__ == "__main__":
    main()
