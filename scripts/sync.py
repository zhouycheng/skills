#!/usr/bin/env python3
"""Interactively synchronize repository skills into installed agent homes."""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from dataclasses import field
from pathlib import Path
from typing import Sequence, TextIO


AGENT_NAMES = (
    ("TRAE CN", ".trae-cn"),
    ("Codex", ".codex"),
    ("Claude", ".claude"),
    ("Gemini", ".gemini"),
)


@dataclass(frozen=True)
class AgentTarget:
    """An installed agent root and the skills directory beneath it."""

    name: str
    root: Path
    skills: Path


@dataclass
class SyncSummary:
    created: int = 0
    replaced: int = 0
    ignored: list[Path] = field(default_factory=list)
    failures: list[tuple[Path, str]] = field(default_factory=list)


def _home_directory(home: Path | None = None) -> Path:
    return Path(home).expanduser() if home is not None else Path.home()


def discover_targets(
    home: Path | None = None,
    system: str | None = None,
) -> tuple[list[AgentTarget], list[str]]:
    """Return installed agent roots and warnings for malformed roots."""

    user_home = _home_directory(home)
    # The four hidden roots have the same layout on both systems. The optional
    # system argument is retained so callers can exercise platform discovery.
    del system

    targets: list[AgentTarget] = []
    warnings: list[str] = []
    for name, directory in AGENT_NAMES:
        root = user_home / directory
        skills = root / "skills"
        if not os.path.lexists(root):
            continue
        if not root.is_dir():
            warnings.append(f"Skipping {name}: root is not a directory: {root}")
            continue
        targets.append(AgentTarget(name=name, root=root, skills=skills))
    return targets, warnings


def discover_skills(repo_root: Path) -> list[Path]:
    """Find direct child skill directories containing a regular SKILL.md."""

    skills: list[Path] = []
    for child in repo_root.iterdir():
        if child.name.startswith(".") or child.is_symlink():
            continue
        if child.is_dir() and (child / "SKILL.md").is_file():
            skills.append(child)
    return sorted(skills, key=lambda path: path.name.casefold())


def _same_directory(left: Path, right: Path) -> bool:
    try:
        return left.resolve() == right.resolve()
    except OSError:
        return left.absolute() == right.absolute()


def _ensure_skills_directory(path: Path) -> None:
    """Create a target skills directory, failing if a file occupies its path."""

    if os.path.lexists(path) and not path.is_dir():
        raise NotADirectoryError(f"target path is not a directory: {path}")
    path.mkdir(parents=True, exist_ok=True)


def sync_skill(source: Path, target_skills: Path, summary: SyncSummary) -> None:
    """Create or replace one destination link, preserving real entries."""

    destination = target_skills / source.name
    try:
        if os.path.lexists(destination):
            if not destination.is_symlink():
                summary.ignored.append(destination)
                return
            destination.unlink()
            os.symlink(str(source.resolve()), str(destination), target_is_directory=True)
            summary.replaced += 1
            return

        os.symlink(str(source.resolve()), str(destination), target_is_directory=True)
        summary.created += 1
    except (OSError, ValueError) as error:
        summary.failures.append((destination, str(error)))


def sync_target(
    repo_root: Path,
    target: AgentTarget,
    sources: Sequence[Path],
    summary: SyncSummary,
) -> None:
    """Synchronize all sources to one target, recording per-target failures."""

    if _same_directory(repo_root, target.skills):
        summary.failures.append((target.skills, "target is the repository itself"))
        return
    try:
        _ensure_skills_directory(target.skills)
    except (OSError, ValueError) as error:
        summary.failures.append((target.skills, str(error)))
        return
    for source in sources:
        sync_skill(source, target.skills, summary)


def _read_key_unix() -> str:
    import sys as _sys

    character = _sys.stdin.read(1)
    if character != "\x1b":
        return character
    next_character = _sys.stdin.read(1)
    if next_character != "[":
        return "esc"
    code = _sys.stdin.read(1)
    return {"A": "up", "B": "down", "C": "right", "D": "left"}.get(code, "unknown")


def _read_key_windows() -> str:
    import msvcrt

    character = msvcrt.getwch()
    if character in ("\x00", "\xe0"):
        return {"H": "up", "P": "down", "K": "left", "M": "right"}.get(
            msvcrt.getwch(), "unknown"
        )
    return character


def _render_targets(
    targets: Sequence[AgentTarget], selected: Sequence[bool], focused: int, output: TextIO
) -> None:
    output.write("\x1b[2J\x1b[H")
    output.write("Select agent skill directories (Space=toggle, Enter=sync, q=cancel)\n\n")
    for index, (target, is_selected) in enumerate(zip(targets, selected)):
        marker = "x" if is_selected else " "
        cursor = ">" if index == focused else " "
        output.write(f"{cursor} [{marker}] {target.name}\n")
        output.write(f"      {target.skills}\n")
    output.flush()


def select_targets(targets: Sequence[AgentTarget], output: TextIO = sys.stdout) -> list[AgentTarget] | None:
    """Run the raw-terminal selector; return None when the user cancels."""

    if not sys.stdin.isatty() or not output.isatty():
        raise RuntimeError("interactive selection requires a terminal")

    selected = [False] * len(targets)
    focused = 0
    is_windows = os.name == "nt"
    old_settings = None
    if not is_windows:
        import termios
        import tty

        old_settings = termios.tcgetattr(sys.stdin.fileno())
        tty.setcbreak(sys.stdin.fileno())

    try:
        while True:
            _render_targets(targets, selected, focused, output)
            key = _read_key_windows() if is_windows else _read_key_unix()
            if key in ("up", "k"):
                focused = (focused - 1) % len(targets)
            elif key in ("down", "j"):
                focused = (focused + 1) % len(targets)
            elif key == " ":
                selected[focused] = not selected[focused]
            elif key in ("\r", "\n"):
                return [target for target, marked in zip(targets, selected) if marked]
            elif key in ("q", "Q", "esc"):
                return None
    finally:
        if old_settings is not None:
            import termios

            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_settings)
        output.write("\x1b[0m\n")
        output.flush()


def _print_summary(summary: SyncSummary, targets: Sequence[AgentTarget], output: TextIO) -> None:
    output.write("\nSync complete.\n")
    output.write(f"  Created: {summary.created}\n")
    output.write(f"  Replaced: {summary.replaced}\n")
    output.write(f"  Ignored: {len(summary.ignored)}\n")
    if summary.ignored:
        for path in summary.ignored:
            output.write(f"    ignored: {path}\n")
    output.write(f"  Failed: {len(summary.failures)}\n")
    for path, error in summary.failures:
        output.write(f"    failed: {path} ({error})\n")
    output.write(f"  Targets: {', '.join(target.name for target in targets)}\n")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo",
        type=Path,
        default=None,
        help="repository root to synchronize (defaults to the parent of scripts/)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    repo_root = (args.repo or Path(__file__).resolve().parent.parent).resolve()
    if not repo_root.is_dir():
        print(f"Repository root does not exist: {repo_root}", file=sys.stderr)
        return 1

    targets, warnings = discover_targets()
    for warning in warnings:
        print(f"Warning: {warning}", file=sys.stderr)
    if not targets:
        print("No supported agent installations were found.")
        return 0

    sources = discover_skills(repo_root)
    if not sources:
        print(f"No skill directories found in {repo_root}.")
        return 0

    print(f"Found {len(sources)} skills in {repo_root}.")
    try:
        chosen = select_targets(targets)
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    if chosen is None:
        print("Cancelled.")
        return 130
    if not chosen:
        print("No targets selected; nothing was changed.")
        return 0

    summary = SyncSummary()
    for target in chosen:
        sync_target(repo_root, target, sources, summary)
    _print_summary(summary, chosen, sys.stdout)
    return 1 if summary.failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
