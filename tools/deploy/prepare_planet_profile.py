#!/usr/bin/env python3
"""Stage a private ground-planet overlay for an existing remote realm.

Does not change live configuration, restart services or touch realm databases.
Apply only during the established backed-up, graceful Core3 shutdown workflow.
"""
import argparse
import json
import re
from pathlib import Path
try:
    from .runtime import ROOT, REMOTE, SUPPORTED_PLANETS, private_write, render_config, render_resources, validate_planets
except ImportError:
    from runtime import ROOT, REMOTE, SUPPORTED_PLANETS, private_write, render_config, render_resources, validate_planets


def prepare(source, destination, planets):
    planets = validate_planets(planets)
    if destination.exists():
        raise ValueError('Use a new private staging directory.')
    config = (source/'config-local.lua').read_text()
    resource = (source/'resource_manager.lua').read_text()
    match = re.search(r'^Core3\.DBPass\s*=\s*"([0-9a-f]{64})"\s*$', config, re.M)
    if not match:
        raise ValueError('Expected existing generated remote database credential.')
    config = render_config(config, match[1], planets)
    resource = render_resources(resource, planets)
    destination.mkdir(parents=True, mode=0o700)
    destination.chmod(0o700)
    private_write(destination/'config-local.lua', config)
    private_write(destination/'resource_manager.lua', resource)
    report = {'schema_version': 1, 'enabled_planets': list(planets),
              'space_enabled': False, 'live_configuration_changed': False,
              'database_changed': False, 'credential_preserved': True,
              'requires': 'Graceful save/stop, realm and configuration backup, then overlay apply and readiness validation.'}
    private_write(destination/'profile.json', json.dumps(report, indent=2)+'\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--planets', default='all', help='all or comma-separated supported ground planets')
    args = parser.parse_args()
    destination = args.destination.resolve()
    if not destination.is_relative_to(ROOT/'runtime/deploy'):
        raise SystemExit('Profile contains a database credential: stage only under ignored runtime/deploy.')
    planets = SUPPORTED_PLANETS if args.planets == 'all' else args.planets.split(',')
    try:
        report = prepare(REMOTE, destination, planets)
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
    print(json.dumps(report))


if __name__ == '__main__':
    main()
