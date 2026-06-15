---
name: git-flow
description: Use ONLY when the project follows Git Flow and the user wants to open or close a feature/feat branch, publish a release, or publish a hotfix.
---

# Git-Flow

Use this skill only when both conditions are true:

- The current project follows Git-Flow or explicitly uses equivalent long-lived branches.
- The user wants to open or close a `feat/*` or `feature/*` branch, publish a release, or publish a hotfix.

This skill is based on Atlassian's Gitflow workflow description: https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow

Do not use this skill for trunk-based development, GitHub Flow, ad-hoc branch cleanup, ordinary commits, or repositories whose branching model is unknown. If the branch names are unclear, inspect the repository and ask one short question before changing branches.

## Naming

Use the shorter canonical names when opening new branches: `main`, `dev`, `feat/`, `release/`, and `hotfix/`.

If an existing project uses longer Git-Flow names such as `master`, `develop`, or `feature/`, recognize them and work with them, but keep the rest of these instructions written in canonical terms.

## Branch Roles

- Production branch: `main`. It stores the official release history and receives version tags. Every commit in `main` is a release and must have its own tag.
- Integration branch: `dev`. It contains the complete development history and integrates finished features.
- Feature branches: `feat/<name>`. They start from `dev` and finish back into `dev`. Features never interact directly with `main`.
- Release branches: `release/<version>`. They start from `dev` after enough features are ready or a scheduled release date approaches. Creating one starts the next release cycle: no new features go into that release branch, only bug fixes, documentation, and other release-oriented work.
- Hotfix branches: `hotfix/<version-or-name>`. They start from `main` and are the only supporting branches that should fork directly from `main`. They contain only an urgent production fix and its release metadata.

Always finish Git Flow branches with non-fast-forward merges. Use `git merge --no-ff <branch>` so feature, release, and hotfix branch boundaries remain visible.

## Hard Gates

- Do not push, create tags, create releases, delete branches, or publish package metadata unless the owner explicitly asks in the current conversation.
- Before the first publishing action, summarize the exact branch heads, commits, version, tags, and commands that will publish state, then get a clear owner OK.
- Never use `git reset --hard`, force-push, amend commits, or interactive Git commands unless explicitly requested.
- If unrelated worktree changes exist, do not modify or revert them. Ignore them if possible, or ask if they block the requested Git Flow action.
- Do not hide unfinished work by stashing without explicit owner approval. Prefer a small WIP commit on the current branch when the owner wants to move away from it.

## Preflight

1. Inspect `git status --short --branch`, `git log --oneline -10`, local branches, remotes, and tags.
2. Identify production and integration branch names from existing branches and project instructions. Use canonical terms `main` and `dev` in the plan unless the actual commands must target existing longer branch names.
3. Identify the current branch and whether it has uncommitted changes.
4. Inspect commits that are about to move between branches, for example `dev..<feat-branch>` or `main..<hotfix-branch>`.
5. Run the repository's safe checks before branch completion or publication. If no standard check is documented, ask or run only clearly safe static checks.
6. If remote state matters, fetch only after confirming that network access is acceptable.

## Opening A Feature Branch

1. Ensure the requested work is normal product development, not release stabilization or urgent production repair.
2. Start from the latest `dev`.
3. Make sure `dev` is current enough for the project policy.
4. Create `feat/<name>` from `dev`.
5. Do not version-bump just because a feature branch is opened.

## Closing A Feature Branch

1. Ensure the feature branch has no uncommitted changes unless those changes should be committed first.
2. Run the repository's safe checks on the feature branch.
3. Switch to `dev`.
4. Merge the feature branch into `dev` with `git merge --no-ff <feat-branch>`.
5. Run safe checks on `dev` after the merge.
6. Push `dev` only after owner approval.
7. Delete the feature branch only after owner approval.

## Publishing A Release

Release publication starts from `dev`, not directly from a feature branch.

If the user asks to publish a release while currently on a feature or `feat` branch:

1. First finish the current feature branch into `dev` if it is intended for this release.
2. Commit any unfinished feature work before leaving the feature branch, or ask if it is not ready.
3. Run safe checks on the feature branch, merge it into `dev` with `git merge --no-ff <feat-branch>`, then run safe checks on `dev`.
4. Only after `dev` contains the intended feature state, create the release branch from `dev`.

Normal release flow:

1. Start from `dev`.
2. Create `release/<version>` from `dev`.
3. Treat the release branch as feature-frozen. Do not merge new features into it. Put only bug fixes, documentation generation, version bumps, changelog updates, lockfile metadata, final release notes, and other release-oriented tasks there.
4. Run safe checks on the release branch.
5. Merge the release branch into `main` with `git merge --no-ff <release-branch>`.
6. Tag the resulting `main` commit with the release version. Every commit in `main` must have its own release tag.
7. Merge the release branch back into `dev` with `git merge --no-ff <release-branch>` so critical release updates are available to new features. If `dev` has progressed since the release branch was cut, resolve conflicts deliberately.
8. Delete the release branch only after owner approval and after both `main` and `dev` have received it.
9. Run safe checks after the `main` and `dev` merges where practical.
10. Push branches, tags, and release artifacts only after owner approval.

## Publishing A Hotfix

Hotfix publication starts from `main`, not from `dev` and not from a feature branch.

If the user asks to publish a hotfix while currently on a feature or `feat` branch:

1. Do not merge the feature branch into `dev` just to start the hotfix.
2. Preserve the feature work first. Prefer committing the current feature changes on the feature branch with a clear WIP or narrow commit message. If the owner does not want a commit, ask before using stash.
3. Leave the feature branch intact and switch to `main`.
4. Create the hotfix branch from `main` only after the feature work is safely parked.

Normal hotfix flow:

1. Start from `main`.
2. Create `hotfix/<version-or-name>` from `main`.
3. Make the minimal urgent fix and any required release metadata or version bump on the hotfix branch.
4. Run safe checks on the hotfix branch.
5. Merge the hotfix branch into `main` with `git merge --no-ff <hotfix-branch>`.
6. Tag the resulting `main` commit with the updated version. Every commit in `main` must have its own release tag.
7. Merge the hotfix branch back into `dev` with `git merge --no-ff <hotfix-branch>` so ongoing development receives the fix and metadata. If a release branch is currently active, merge the hotfix into that release branch instead of, or before, `dev` according to the project policy.
8. Delete the hotfix branch only after owner approval and after the required target branches have received it.
9. Resolve conflicts in favor of preserving both the `main` fix and valid ongoing `dev` or release-branch changes.
10. Push branches, tags, and release artifacts only after owner approval.

## Versioning Principles

- Feature branches do not own release version bumps.
- Release branches own planned release version bumps and release-oriented metadata.
- Hotfix branches own urgent production patch version bumps and hotfix metadata.
- Every commit in `main` is a release commit and must have its own tag.
- Production tags belong on `main` history after release or hotfix completion, not on arbitrary feature commits.

## Final Report

Report the final state with:

- Branches created, merged, or left untouched.
- Exact commits moved into `dev` or `main`.
- Version bump commit, if any.
- Tags created, if any.
- Checks run and checks intentionally skipped.
- Publishing actions performed or intentionally left pending.
