#!/usr/bin/env python3
"""Export the original SWG UI main-title music from user-provided local TREs.

Uses the existing SND decoder/Vorbis conversion. No game media is downloaded.
The selection is verified against the pinned original client's CuiManager.
"""
import argparse
import hashlib
import json
import math
import re
import subprocess
from pathlib import Path
from prepare_environment import EnvironmentImporter

ROOT = Path(__file__).resolve().parents[2]
SOUND = 'sound/music_main_title.snd'
REVISION = '949451032647e45e42c3aaef3f41b132c8af36e3'
SELECTION_PATH = 'src/engine/client/library/clientUserInterface/src/shared/core/CuiManager.cpp'
SELECTION_HASH = '96e968e98dbdd016f2e6ecd64a9bb098357e95964f691471e783b14ad31c28d9'
SELECTION_URL = f'https://github.com/SWG-Source/client-tools/blob/{REVISION}/{SELECTION_PATH}'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def probe(path):
    command = ['ffprobe', '-v', 'error', '-show_entries',
               'stream=codec_name,sample_rate,channels:format=duration', '-of', 'json', str(path)]
    result = json.loads(subprocess.run(command, check=True, capture_output=True).stdout)
    stream = result['streams'][0]
    duration = float(result['format']['duration'])
    if stream['codec_name'] != 'vorbis' or duration <= 1 or not math.isfinite(duration):
        raise ValueError(f'Invalid converted login audio: {result}')
    decoded = subprocess.run(['ffmpeg', '-hide_banner', '-nostdin', '-i', str(path),
                              '-af', 'volumedetect', '-f', 'null', '-'], capture_output=True)
    if decoded.returncode:
        raise ValueError(decoded.stderr.decode(errors='replace')[-1000:])
    text = decoded.stderr.decode(errors='replace')
    peak = re.search(r'max_volume: ([-\d.]+) dB', text)
    if not peak or float(peak[1]) < -90:
        raise ValueError('Converted login audio is silent or lacks a valid decoded peak')
    return {'codec': stream['codec_name'], 'sample_rate': int(stream['sample_rate']),
            'channels': int(stream['channels']), 'duration_seconds': duration,
            'decoded_peak_db': float(peak[1]), 'full_decode_passed': True}


def prepare(tre_dir, output, selection_source=None):
    selection = {'repository': 'SWG-Source/client-tools', 'revision': REVISION,
                 'path': SELECTION_PATH, 'sha256': SELECTION_HASH, 'url': SELECTION_URL,
                 'symbol': 'CuiManager::ms_musicName', 'selection_line': 311,
                 'playback_lines': [1067, 1261], 'local_source_verified': False}
    if selection_source is not None and selection_source.is_file():
        raw = selection_source.read_bytes()
        if digest(raw) != SELECTION_HASH or f'"{SOUND}"'.encode() not in raw:
            raise ValueError('Original client selection source differs from the pinned verified revision')
        selection['local_source_verified'] = True
    importer = EnvironmentImporter(tre_dir, output)
    if not importer.sound(SOUND):
        raise ValueError(f'Unable to decode original login music: {importer.failures}')
    sound = importer.sounds[SOUND]
    if sound['spatial'] or len(sound['samples']) != 1:
        raise ValueError('Expected the original non-spatial single-sample main-title cue')
    samples = []
    for relative, original in zip(sound['samples'], sound['sample_sources']):
        path = output / relative
        samples.append({'path': relative, 'source': original, 'sha256': digest(path.read_bytes()),
                        'bytes': path.stat().st_size, **probe(path)})
    result = {'schema_version': 1, 'sound': SOUND, 'samples': sound['samples'],
              'loop': sound['loop'], 'volume': sound['volume'],
              'fade_in_seconds': sum(sound['fade_in_seconds']) / 2,
              'fade_out_seconds': sum(sound['fade_out_seconds']) / 2,
              'source': {'selection': selection, 'dependencies': importer.dependencies,
                         'sample_sources': sound['sample_sources'],
                         'loop_count_range': sound['loop_count_range'],
                         'start_delay_seconds': sound['start_delay_seconds'],
                         'delay_seconds': sound['delay_seconds'],
                         'fade_in_range_seconds': sound['fade_in_seconds'],
                         'fade_out_range_seconds': sound['fade_out_seconds'],
                         'source_numeric_tail_hex': sound['source_numeric_tail_hex'],
                         'source_layout': sound['source_layout']},
              'sample_metadata': samples, 'failures': importer.failures,
              'conversion': {'tool': 'ffmpeg', 'codec': 'libvorbis', 'quality': 5,
                             'pipeline': 'tools/assets/prepare_environment.py EnvironmentImporter.audio'}}
    temporary = output / 'catalog.json.tmp'
    temporary.write_text(json.dumps(result, indent=2) + '\n')
    temporary.replace(output / 'catalog.json')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tre-dir', type=Path, default=ROOT/'runtime/assets/active_tre')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/assets/login')
    parser.add_argument('--selection-source', type=Path, default=ROOT/'runtime/research/swg-login/CuiManager.cpp')
    parser.add_argument('--report', type=Path, default=ROOT/'runtime/evidence/login-assets-validation.json')
    args = parser.parse_args()
    try:
        catalog = prepare(args.tre_dir, args.out, args.selection_source)
        report = {'passed': True, 'catalog': str(args.out/'catalog.json'), 'sound': catalog['sound'],
                  'loop': catalog['loop'], 'fade_out_seconds': catalog['fade_out_seconds'],
                  'source': catalog['source'], 'samples': catalog['sample_metadata'], 'failures': []}
    except Exception as error:
        report = {'passed': False, 'failures': [{'phase': 'original_login_audio_export', 'error': str(error)}]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
