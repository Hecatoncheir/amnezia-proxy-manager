import unittest

from release import notes, prepare, version


class ReleaseTest(unittest.TestCase):
    def test_tags(self):
        self.assertEqual(version("v1.2.3-rc.1"), "1.2.3-rc.1")
        for tag in ["1.2.3", "v01.2.3", "v1.2", "v1.2.3-rc.01", "v1.2.3\n"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                version(tag)

    def test_notes_boundaries(self):
        history = "## Unreleased\nБудущее\n## v1.2.3 — дата\n### Исправлено\nОшибка\n## v1.2.2\nСтарое\n"
        self.assertEqual(notes(history, "v1.2.3"), "### Исправлено\nОшибка\n")
        for history in ["## v1.2.3\n", "## v1.2.3\nА\n## v1.2.3\nБ", "## v1.2.2\nА"]:
            with self.assertRaises(ValueError):
                notes(history, "v1.2.3")

    def test_prepare(self):
        spec, history = prepare("name: app\nversion: 0.1.0+1\n", "## Unreleased\n- Исправление\n## v0.1.0\n- Начало\n", "v0.1.1")
        self.assertIn("version: 0.1.1+2", spec)
        self.assertEqual(notes(history, "v0.1.1"), "- Исправление\n")
        self.assertIn("## Unreleased\n", history)

    def test_empty_prepare_rejected(self):
        with self.assertRaises(ValueError):
            prepare("version: 0.1.0+1\n", "## Unreleased\n\n## v0.1.0\nНачало", "v0.1.1")


if __name__ == "__main__":
    unittest.main()
