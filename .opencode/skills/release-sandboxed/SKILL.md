---
name: release-sandboxed
description: Use when preparing a sandboxed release branch, merging feature branches into a release, tagging sandboxed and homebrew-sandboxed, updating the Homebrew formula, or publishing a GitHub release.
---

# Release Sandboxed

Use this skill only for the `sandboxed` project release workflow and its Homebrew tap checkout under `homebrew/`.

The core repository is GitFlow-based. The Homebrew tap is not GitFlow-based and uses only `main`.

## Hard Gates

- Do not push, create tags, create GitHub releases, delete branches, or publish Homebrew tap changes unless the owner explicitly asks for that release action in the current conversation.
- Before the first network or publishing action, summarize the exact commits, version, tags, repositories, and commands that will publish state, then get a clear owner OK.
- Do not run real container starts unless the owner explicitly approved them or already ran `just check-real-starts` after the last relevant code change.
- Do not delete the feature branch unless the owner explicitly asks. Leaving the branch checked out or available for review is acceptable.
- Never use `git reset --hard`, force-push, amend commits, or interactive Git commands.
- If unexpected unrelated worktree changes exist, do not modify or revert them. Either ignore unrelated files or ask if they block the release.

## Repositories

- Core repository: `/home/kz/Projects/sandboxed`, remote `Kirill-Znamenskiy/sandboxed`, GitFlow branches `dev` and `main`.
- Tap repository: `/home/kz/Projects/sandboxed/homebrew`, remote `Kirill-Znamenskiy/homebrew-sandboxed`, branch `main` only.
- Read the applicable `AGENTS.md` before changing either repository. The tap has its own `homebrew/AGENTS.md`.

## Preflight

1. In the core repository, inspect `git status --short --branch`, `git log --oneline -10`, and the selected feature branch commits since `dev`.
2. In the tap repository, inspect `git status --short --branch`, `git log --oneline -10`, and the formula state.
3. Confirm the release version. If the owner did not specify it, infer the next patch version from existing tags, then ask before creating or editing a release branch.
4. Confirm which feature branches should be collected into the release branch.
5. Check that each feature branch contains all intended commits and no uncommitted release work remains.
6. Run `just check` in the core repository before any merge.
7. For runtime-affecting changes, run or require owner approval for `just check-real-starts`. If the owner already ran it after the latest relevant change, record that result instead of rerunning.

## Core Release Flow

1. Switch to `dev` and make sure it is up to date with its remote before cutting a release branch.
2. Create or switch to the named release branch from `dev`, such as `release/vX.Y.Z`.
3. Merge each selected feature branch into the release branch with `git merge --no-ff <feature-branch>`.
4. Run `just check` on the release branch. If the release depends on actual startup, also handle `just check-real-starts` under the hard gate above.
5. Make the version bump on the release branch only. Update every source file that reports or documents the release version, then run `just check` and commit the bump separately.
6. Merge the release branch back to `dev` with `git merge --no-ff <release-branch>` so `dev` receives the exact released state.
7. Run `just check` on `dev`.
8. Push `dev` only after owner approval.
9. Switch to `main` and make sure it is up to date with its remote.
10. Merge the release branch into `main` with `git merge --no-ff <release-branch>` for the deliberate release checkpoint.
11. Run `just check` on `main`.
12. Create an annotated core tag `vX.Y.Z` on `main` after verification.
13. Push `main` and the core tag only after owner approval.

## GitHub Release

1. Create the GitHub release in `Kirill-Znamenskiy/sandboxed` from the pushed core tag.
2. Use a concise title such as `vX.Y.Z`.
3. Base notes on the commits included since the previous tag. Mention user-visible changes, verification, and packaging impact.
4. Prefer `gh release create vX.Y.Z --repo Kirill-Znamenskiy/sandboxed --title vX.Y.Z --notes-file <file>` after preparing notes in a temporary file.

## Homebrew Tap Flow

1. After the core tag is pushed and the GitHub release exists, compute the release tarball SHA from `https://github.com/Kirill-Znamenskiy/sandboxed/archive/refs/tags/vX.Y.Z.tar.gz`.
2. In the tap repository, stay on `main`. Do not create GitFlow branches there.
3. Update `Formula/sandboxed.rb` with the new tag URL, `version`, and `sha256`.
4. Keep the formula installing `src` and `targets`, exposing both `sandboxed` and `sbxd`, depending on generic `python`, and using release tarballs with `sha256`.
5. Validate the formula with safe local checks first, such as Ruby syntax or `brew audit` when available.
6. If running Homebrew install/test commands could fetch network resources or mutate Homebrew state, summarize that and get owner approval first.
7. Commit the formula update on tap `main` with a message like `Update sandboxed to X.Y.Z`.
8. Create an annotated tap tag `vX.Y.Z` on tap `main` if the owner wants tags in both repositories.
9. Push tap `main` and the tap tag only after owner approval.

## Final Report

Report the final state with:

- Core branch and commit pushed to `dev`.
- Core branch and commit pushed to `main`.
- Core release branch name and version bump commit.
- Core tag and GitHub release URL.
- Tap commit and tap tag.
- Checks run, including whether `just check-real-starts` was run by the owner or by the assistant.
- Any skipped checks and the reason.
