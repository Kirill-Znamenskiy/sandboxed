---
name: git-flow
description: Use ONLY when the project follows Git Flow and the user wants to open or close a feature/feat branch, publish a release, or publish a hotfix.
---

# Git Flow

Use this skill only when both conditions are true:

- The current project follows Git Flow or explicitly uses equivalent long-lived branches such as `main`/`master` plus `dev`/`develop`.
- The user wants to open or close a `feature/*` or `feat/*` branch, publish a release, or publish a hotfix.

Do not use this skill for trunk-based development, GitHub Flow, ad-hoc branch cleanup, ordinary commits, or repositories whose branching model is unknown. If the branch names are unclear, inspect the repository and ask one short question before changing branches.

## Branch Roles

- Production branch: `main` or `master`. Released code and release tags live here.
- Integration branch: `dev` or `develop`. Completed features collect here before release preparation.
- Feature branches: `feature/<name>` or `feat/<name>`. Start from integration and finish back into integration.
- Release branches: `release/<version>`. Start from integration, collect the intended release state, receive the version bump, then merge into production and integration.
- Hotfix branches: `hotfix/<version-or-name>`. Start from production, contain only the urgent fix and its release metadata, then merge into production and integration.

Prefer `--no-ff` merges for Git Flow branch finishes so branch boundaries remain visible. Do not fast-forward feature, release, or hotfix completion unless the owner explicitly asks.

## Hard Gates

- Do not push, create tags, create releases, delete branches, or publish package metadata unless the owner explicitly asks in the current conversation.
- Before the first publishing action, summarize the exact branch heads, commits, version, tags, and commands that will publish state, then get a clear owner OK.
- Never use `git reset --hard`, force-push, amend commits, or interactive Git commands unless explicitly requested.
- If unrelated worktree changes exist, do not modify or revert them. Ignore them if possible, or ask if they block the requested Git Flow action.
- Do not hide unfinished work by stashing without explicit owner approval. Prefer a small WIP commit on the current branch when the owner wants to move away from it.

## Preflight

1. Inspect `git status --short --branch`, `git log --oneline -10`, local branches, remotes, and tags.
2. Identify production and integration branch names from existing branches and project instructions.
3. Identify the current branch and whether it has uncommitted changes.
4. Inspect commits that are about to move between branches, for example `<integration>..<feature>` or `<production>..<hotfix>`.
5. Run the repository's safe checks before branch completion or publication. If no standard check is documented, ask or run only clearly safe static checks.
6. If remote state matters, fetch only after confirming that network access is acceptable.

## Opening A Feature Branch

1. Ensure the requested work is normal product development, not release stabilization or urgent production repair.
2. Start from the integration branch: `dev` or `develop`.
3. Make sure the integration branch is current enough for the project policy.
4. Create `feature/<name>` or `feat/<name>` from integration.
5. Do not version-bump just because a feature branch is opened.

## Closing A Feature Branch

1. Ensure the feature branch has no uncommitted changes unless those changes should be committed first.
2. Run the repository's safe checks on the feature branch.
3. Switch to the integration branch.
4. Merge the feature branch with `git merge --no-ff <feature-or-feat-branch>`.
5. Run safe checks on integration after the merge.
6. Push integration only after owner approval.
7. Delete the feature branch only after owner approval.

## Publishing A Release

Release publication starts from integration, not directly from a feature branch.

If the user asks to publish a release while currently on a feature or `feat` branch:

1. First finish the current feature branch into integration if it is intended for this release.
2. Commit any unfinished feature work before leaving the feature branch, or ask if it is not ready.
3. Run safe checks on the feature branch, merge it into integration with `--no-ff`, then run safe checks on integration.
4. Only after integration contains the intended feature state, create the release branch from integration.

Normal release flow:

1. Start from the integration branch.
2. Create `release/<version>` from integration.
3. Merge any additional selected feature branches into the release branch with `--no-ff`, if the project collects features there instead of directly in integration.
4. Make release-only changes on the release branch: version bump, changelog, lockfile metadata, or final release notes.
5. Run safe checks on the release branch.
6. Merge the release branch into the production branch with `--no-ff`.
7. Tag the production branch at the release merge commit, usually with an annotated tag such as `vX.Y.Z`.
8. Merge the release branch back into integration with `--no-ff` so integration receives the exact released version bump and release metadata.
9. Run safe checks after the production and integration merges where practical.
10. Push branches, tags, and release artifacts only after owner approval.

## Publishing A Hotfix

Hotfix publication starts from production, not from integration and not from a feature branch.

If the user asks to publish a hotfix while currently on a feature or `feat` branch:

1. Do not merge the feature branch into integration just to start the hotfix.
2. Preserve the feature work first. Prefer committing the current feature changes on the feature branch with a clear WIP or narrow commit message. If the owner does not want a commit, ask before using stash.
3. Leave the feature branch intact and switch to the production branch.
4. Create the hotfix branch from production only after the feature work is safely parked.

Normal hotfix flow:

1. Start from the production branch: `main` or `master`.
2. Create `hotfix/<version-or-name>` from production.
3. Make the minimal urgent fix and any required release metadata or version bump on the hotfix branch.
4. Run safe checks on the hotfix branch.
5. Merge the hotfix branch into production with `--no-ff`.
6. Tag the production branch at the hotfix merge commit.
7. Merge the hotfix branch back into integration with `--no-ff` so ongoing development receives the fix and metadata.
8. Resolve conflicts in favor of preserving both the production fix and valid ongoing integration changes.
9. Push branches, tags, and release artifacts only after owner approval.

## Versioning Principles

- Feature branches do not own release version bumps.
- Release branches own planned release version bumps.
- Hotfix branches own urgent patch version bumps.
- Production tags should point at production merge commits, not at arbitrary feature commits.

## Final Report

Report the final state with:

- Branches created, merged, or left untouched.
- Exact commits moved into integration or production.
- Version bump commit, if any.
- Tags created, if any.
- Checks run and checks intentionally skipped.
- Publishing actions performed or intentionally left pending.
