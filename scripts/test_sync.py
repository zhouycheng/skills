import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sync


class SyncTests(unittest.TestCase):
    def test_discovers_existing_agent_roots_and_missing_skills_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".codex").mkdir()
            targets, warnings = sync.discover_targets(home=home, system="Darwin")
            self.assertEqual(warnings, [])
            self.assertEqual([target.name for target in targets], ["Codex"])
            self.assertEqual(targets[0].skills, home / ".codex" / "skills")
            self.assertFalse(targets[0].skills.exists())

    def test_builds_all_supported_agent_skill_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            for _, hidden_name in sync.AGENT_NAMES:
                (home / hidden_name).mkdir()
            targets, warnings = sync.discover_targets(home=home, system="Windows")
            self.assertEqual(warnings, [])
            self.assertEqual(
                [target.skills for target in targets],
                [home / hidden_name / "skills" for _, hidden_name in sync.AGENT_NAMES],
            )

    def test_skips_agent_root_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".claude").write_text("file")
            targets, warnings = sync.discover_targets(home=home)
            self.assertEqual(targets, [])
            self.assertIn("not a directory", warnings[0])

    def test_discovers_direct_skill_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "z-skill").mkdir()
            (root / "z-skill" / "SKILL.md").write_text("# Z")
            (root / "empty").mkdir()
            (root / ".hidden").mkdir()
            self.assertEqual([path.name for path in sync.discover_skills(root)], ["z-skill"])

    def test_empty_discovery_results_are_supported(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(sync.discover_skills(root), [])
            self.assertEqual(sync.discover_targets(home=root)[0], [])

    def test_creates_and_replaces_links_but_ignores_entities(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "skill"
            source.mkdir()
            target = root / "target"
            target.mkdir()
            summary = sync.SyncSummary()

            sync.sync_skill(source, target, summary)
            self.assertTrue((target / "skill").is_symlink())
            self.assertEqual(summary.created, 1)

            sync.sync_skill(source, target, summary)
            self.assertEqual(summary.replaced, 1)

            entity = target / "entity-source"
            entity.mkdir()
            sync.sync_skill(root / "entity-source", target, summary)
            self.assertEqual(len(summary.ignored), 1)

            (target / "skill").unlink()
            (target / "skill").mkdir()
            sync.sync_skill(source, target, summary)
            self.assertEqual(len(summary.ignored), 2)

            (target / "skill").rmdir()
            (target / "skill").write_text("keep")
            sync.sync_skill(source, target, summary)
            self.assertEqual(len(summary.ignored), 3)

    def test_replaces_broken_link(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "skill"
            source.mkdir()
            target = root / "target"
            target.mkdir()
            destination = target / "skill"
            destination.symlink_to(root / "missing", target_is_directory=True)
            summary = sync.SyncSummary()
            sync.sync_skill(source, target, summary)
            self.assertTrue(destination.is_symlink())
            self.assertEqual(summary.replaced, 1)

    def test_reports_link_creation_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "skill"
            source.mkdir()
            target = root / "target"
            target.mkdir()
            summary = sync.SyncSummary()
            with mock.patch.object(sync.os, "symlink", side_effect=OSError("not permitted")):
                sync.sync_skill(source, target, summary)
            self.assertEqual(len(summary.failures), 1)
            self.assertIn("not permitted", summary.failures[0][1])

    def test_sync_target_creates_missing_skills_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "skill"
            source.mkdir()
            target = sync.AgentTarget("Codex", root / ".codex", root / ".codex" / "skills")
            summary = sync.SyncSummary()
            sync.sync_target(root, target, [source], summary)
            self.assertTrue((target.skills / "skill").is_symlink())


if __name__ == "__main__":
    unittest.main()
