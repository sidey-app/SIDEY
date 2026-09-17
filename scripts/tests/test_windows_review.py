import sys
from pathlib import Path
import unittest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "skills"))

from workflow import WorkflowError, verify_windows_run  # noqa: E402


class WindowsReviewTests(unittest.TestCase):
    def test_requires_current_main_push_and_actual_smoke(self):
        metadata = {
            "head_sha": "current",
            "head_branch": "main",
            "event": "push",
            "status": "completed",
            "conclusion": "success",
            "path": ".github/workflows/ci.yml",
        }
        jobs = [
            {
                "name": "Windows build and tests",
                "conclusion": "success",
                "steps": [
                    {
                        "name": "Run Windows app smoke",
                        "conclusion": "success",
                    }
                ],
            }
        ]
        verify_windows_run("current", metadata, jobs)

        for field in metadata:
            with self.subTest(field=field), self.assertRaises(WorkflowError):
                verify_windows_run(
                    "current",
                    {**metadata, field: "other"},
                    jobs,
                )

        invalid_jobs = [
            [],
            [
                {
                    "name": "Windows build and tests",
                    "conclusion": "success",
                    "steps": [],
                }
            ],
            [
                {
                    "name": "Windows build and tests",
                    "conclusion": "skipped",
                }
            ],
            [
                {
                    "name": "Windows build and tests",
                    "conclusion": "success",
                    "steps": [
                        {
                            "name": "Run Windows app smoke",
                            "conclusion": "skipped",
                        }
                    ],
                }
            ],
        ]
        for invalid in invalid_jobs:
            with (
                self.subTest(jobs=invalid),
                self.assertRaises(WorkflowError),
            ):
                verify_windows_run("current", metadata, invalid)


if __name__ == "__main__":
    unittest.main()
