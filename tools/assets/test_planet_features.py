import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from complete_planet_features import update_world_diagnostics

class PlanetDiagnostics(unittest.TestCase):
    def test_legacy_reports_are_optional_and_prior_findings_survive(self):
        with tempfile.TemporaryDirectory() as folder:
            row={'world':str(Path(folder)/'world.json'),'collision_coverage':{'authored':2},'architecture_omissions':[{'template':'object/building/missing.iff'}]}
            update_world_diagnostics(row)
            self.assertEqual(row['collision_coverage'],{'authored':2})
            self.assertEqual(len(row['architecture_omissions']),1)
            self.assertEqual(set(row['world_diagnostic_sources'].values()),{'retained_previous_catalog'})
            fresh={'world':row['world']};update_world_diagnostics(fresh)
            self.assertNotIn('collision_coverage',fresh)
            self.assertEqual(set(fresh['world_diagnostic_sources'].values()),{'unavailable'})
            (Path(folder)/'collision_report.json').write_text(json.dumps({'counts':{'authored':3}}))
            update_world_diagnostics(row)
            self.assertEqual(row['collision_coverage'],{'authored':3})
            self.assertEqual(row['world_diagnostic_sources']['collision_report.json'],'report_present')
