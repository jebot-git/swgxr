"""Mock process boundaries; never touch actual systemd/Core3 processes."""
import subprocess
import unittest
from pathlib import Path
from unittest.mock import Mock,patch
from tools.deploy import scheduled_restart as restart

class RestartTests(unittest.TestCase):
    def test_native_save_precedes_supervisor_stop_and_restart(self):
        calls=[]
        def run(args):
            calls.append(args)
            return 'active' if args[1] in ('is-active','show') else ''
        with patch.object(restart,'event'):
            restart.restart(run=run,check_health=lambda:True,pause=lambda _:None)
        self.assertEqual(calls[1],['systemctl','stop',*restart.FRONTENDS])
        self.assertEqual(calls[2][-1],'stop-core')
        self.assertEqual(calls[3],['systemctl','stop','swgxr-core3.service'])
        self.assertEqual(calls[4],['systemctl','start',*restart.SERVICES])
        text=str(calls)
        for forbidden in ('kill','reboot','swgxr-db.service','swgxr-container.service','bootstrap','init-db'):
            self.assertNotIn(forbidden,text)

    def test_graceful_timeout_never_stops_native_supervisor_or_starts_another_core(self):
        calls=[]
        def run(args):
            calls.append(args)
            if args[-1]=='stop-core':raise subprocess.CalledProcessError(1,args)
            return 'active'
        with patch.object(restart,'event'),self.assertRaises(subprocess.CalledProcessError):
            restart.restart(run=run,check_health=lambda:True)
        self.assertEqual(len(calls),3)
        self.assertNotIn(['systemctl','stop','swgxr-core3.service'],calls)
        self.assertFalse(any(c[1]=='start' for c in calls))

    def test_inactive_target_not_started(self):
        run=Mock(return_value='inactive')
        with patch.object(restart,'event'):restart.restart(run=run)
        run.assert_called_once_with(['systemctl','show','--property=ActiveState','--value','swgxr.target'])

    def test_native_readiness_retries_and_failure_is_visible(self):
        run=Mock(return_value='active');health=Mock(side_effect=[False,OSError(),True]);pause=Mock()
        with patch.object(restart,'event'):restart.restart(run=run,check_health=health,pause=pause)
        self.assertEqual(health.call_count,3);self.assertEqual(pause.call_count,2)
        with patch.object(restart,'event'),self.assertRaisesRegex(RuntimeError,'readiness'):
            restart.restart(run=run,check_health=lambda:False,pause=lambda _:None)

    def test_exact_utc_timer_without_catchup_or_random_delay(self):
        units=Path(restart.ROOT/'tools/deploy/systemd')
        timer=(units/'swgxr-daily-restart.timer.in').read_text()
        for line in ('OnCalendar=*-*-* 05:00:00 UTC','Persistent=false','AccuracySec=1s','RandomizedDelaySec=0','Unit=swgxr-daily-restart.service'):
            self.assertIn(line,timer)
        service=(units/'swgxr-daily-restart.service.in').read_text()
        self.assertIn('scheduled_restart.py',service)
        self.assertNotIn('Restart=always',service)
        self.assertIn('swgxr-daily-restart.timer',(units/'swgxr.target.in').read_text())

if __name__=='__main__':unittest.main()
