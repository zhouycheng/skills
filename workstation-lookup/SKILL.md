---
name: workstation-lookup
description: Quickly locate and verify this Mac's installed development capabilities, CLI paths, Android/Flutter readiness and managed configuration from any project. Use for environment questions or tool prerequisites; workstation maintenance belongs to the workstation-config project skills.
---

# Workstation lookup

Find the workstation repository at `~/workstation-config`. Its desired package and environment declarations live in `macos/manifest/`; `~/.local/state/env/inventory.json` is the local observed snapshot. First read the snapshot's `generated_at`, `config_digest` and the relevant section's `status`. `~/workstation-config/bin/workstation inventory status` reports freshness. A snapshot older than 12 hours, whose configuration digest changed, or with `unknown` in the relevant section cannot confirm current availability. Run `inventory refresh` for a new local observation, then verify the specific command or component before relying on it. The refresh is local and does not install packages, prepare Gradle distributions or start an emulator.

Use `~/workstation-config/codex/environment/INDEX.md` as a capability navigation page. `macos/manifest/capabilities.json` lists observation targets, while `Brewfile` lists desired packages. Treat `codex/environment/development.md` as a dated historical record. If the checkout or snapshot is missing, report that and perform only the task-specific read-only checks available locally.

This skill is for lookup and targeted verification from other repositories. For editing desired configuration, deploying components or installing packages, open `~/workstation-config` as the current project and follow its `.agents/skills/workstation-audit`, `workstation-provision`, `android-flutter-env` or `macos-shell-env` skill as appropriate. Do not copy their scripts or maintain a second manifest here.
