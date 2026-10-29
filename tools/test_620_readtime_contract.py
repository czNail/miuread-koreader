"""6.2 cross-layer reading-time and release-source contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent

def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

class TimeContracts(unittest.TestCase):
    def test_independent_periodic_time_and_shutdown_flush(self):
        s = source('miuread.koplugin/miuread/read_report_service.lua')
        self.assertIn('next_due = run_report(control, elapsed, false, "interval")', s)
        self.assertIn('next_due = run_report(control, elapsed, true, tostring(control.flush_reason or "stop"))', s)
        self.assertIn('Config.READ_TIME_BEST_EFFORT==true', s)
        self.assertIn('request_dispatched=result.request_dispatched==true', s)
        self.assertIn('(not time_only and (control.position_safe', s)

    def test_time_gets_one_session_web_anchor_but_progress_is_still_native(self):
        s = source('miuread.koplugin/miuread/legacy/read_report_worker.lua')
        time = s.split('    if reading_time_compat then', 1)[1].split('    local accepted, result',1)[0]
        self.assertIn('refresh_remote_anchor(client,book_id,book)',time)
        self.assertIn('if not position_override then',time)
        self.assertIn('book.session_time_anchor_session=session_id',time)
        self.assertIn('normalize_cloud_anchor(nil,book)',time)
        self.assertIn('request_dispatched=false',time)
        self.assertNotIn('estimate_position(book,progress_ratio)',time)
        self.assertIn('validate_terminal_progress(book,position)',s)

    def test_foreground_time_control_has_no_native_position_dependency(self):
        s=source('miuread.koplugin/miuread/sync.lua')
        a=s.split('function Sync:_write_daemon_control(',1)[1].split('function Sync:_readtime_recovery_path()',1)[0]
        self.assertIn('if not time_only then',a)
        self.assertIn('position_safe = time_only or',a)
        self.assertIn('self:_position_for_report(nil,precise_position)',a)
        self.assertIn('READ_TIME_BEST_EFFORT = true',source('miuread.koplugin/miuread/config.lua'))

    def test_stable_release_is_tag_immutable(self):
        s=source('.github/workflows/release.yml')
        self.assertIn("github.event_name == 'push' && github.ref || 'main'",s)
        self.assertIn('if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then',s)
        self.assertIn('仅校验 Tag 对应源码',s)

    def test_identity(self):
        self.assertIn('VERSION = "6.2.0-beta.2"',source('miuread.koplugin/miuread/config.lua'))
        self.assertIn('version = "6.2.0-beta.2"',source('miuread.koplugin/_meta.lua'))
        self.assertIn('## 6.2.0-beta.2',source('CHANGELOG.md'))

if __name__=='__main__': unittest.main()
