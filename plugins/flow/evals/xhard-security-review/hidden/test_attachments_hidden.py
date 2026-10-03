import os
import tempfile
import unittest

from fileserve.serve import download_attachment


class TestDownloadAttachmentHidden(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = os.path.realpath(self._tmp.name)
        att = os.path.join(self.root, "attachments")
        os.makedirs(os.path.join(att, "docs"))
        os.makedirs(os.path.join(self.root, "attachments-evil"))
        self._write(os.path.join(att, "a.txt"), b"AAA")
        self._write(os.path.join(att, "docs", "manual.pdf"), b"MANUAL")
        self._write(os.path.join(self.root, "secret.txt"), b"SECRET")
        self._write(os.path.join(self.root, "attachments-evil", "x.txt"), b"EVIL")
        os.symlink(os.path.join(self.root, "secret.txt"), os.path.join(att, "leak.txt"))
        os.symlink(os.path.join(self.root, "attachments-evil"), os.path.join(att, "leakdir"))
        os.symlink(os.path.join(att, "a.txt"), os.path.join(att, "alias.txt"))

    @staticmethod
    def _write(path, data):
        with open(path, "wb") as fh:
            fh.write(data)

    def test_reads_a_plain_file(self):
        self.assertEqual(download_attachment(self.root, "a.txt"), b"AAA")

    def test_reads_a_file_in_a_subfolder(self):
        self.assertEqual(download_attachment(self.root, "docs/manual.pdf"), b"MANUAL")

    def test_parent_steps_that_stay_inside_are_fine(self):
        self.assertEqual(download_attachment(self.root, "docs/../a.txt"), b"AAA")

    def test_a_link_that_stays_inside_is_fine(self):
        self.assertEqual(download_attachment(self.root, "alias.txt"), b"AAA")

    def test_dotdot_escape_is_refused(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "../secret.txt")

    def test_deep_dotdot_escape_is_refused(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "docs/../../secret.txt")

    def test_absolute_path_is_refused(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, os.path.join(self.root, "secret.txt"))

    def test_sibling_folder_sharing_the_prefix_is_refused(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "../attachments-evil/x.txt")

    def test_a_link_to_a_file_outside_is_refused(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "leak.txt")

    def test_a_link_to_a_folder_outside_is_refused(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "leakdir/x.txt")

    def test_an_escape_is_refused_even_when_the_target_does_not_exist(self):
        with self.assertRaises(ValueError):
            download_attachment(self.root, "../no-such-file.txt")

    def test_missing_file_inside_raises_file_not_found(self):
        with self.assertRaises(FileNotFoundError):
            download_attachment(self.root, "nope.txt")
