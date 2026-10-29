"""Guard against release verifier requiring removed periodic Legacy GET."""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]

class ReleaseVerifierContract(unittest.TestCase):
    def test_web_session_snapshot_contract_not_legacy_get(self):
        source=(ROOT/'tools/verify_600_beta1.py').read_text(encoding='utf-8')
        self.assertIn('ReadReport session-scoped Web-time echo with fail-closed validation retained',source)
        self.assertIn("'refresh_remote_anchor(client,book_id,book)' not in time_branch",source)
        self.assertIn("'same_book and from_web and fresh' in time_branch",source)
        self.assertIn("'request_dispatched=false' in time_branch",source)

    def test_release_verifier_passes(self):
        result=subprocess.run([sys.executable,str(ROOT/'tools/verify_600_beta1.py')],cwd=ROOT,
                              capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
        self.assertIn('failures=0',result.stdout)

if __name__=='__main__':unittest.main()
