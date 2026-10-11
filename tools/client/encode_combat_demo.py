#!/usr/bin/env python3
"""Encode the live Godot demo with recorded wall-clock timing and game audio."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=ROOT/'runtime/action-prototype/live-view')
    parser.add_argument('--out', type=Path, default=ROOT/'runtime/action-prototype/combat-animation-demo.mp4')
    parser.add_argument('--required-roles', nargs='+', choices=('action_worrt', 'action_pistol', 'action_heal'), default=['action_worrt','action_pistol','action_heal'])
    args = parser.parse_args()
    directory = args.directory.resolve()
    evidence = json.loads((directory/'video-frames.json').read_text())
    frames = evidence['frames']
    assert len(frames) > 1 and evidence['renderer'] == 'forward_plus' and not evidence['server_mocked']
    counts = Counter((pose['pose']['key'], 'hold' if pose['pose']['hold'] else 'play')
                     for frame in frames for pose in frame['poses'])
    for key in args.required_roles:
        assert counts[key, 'hold'] > 0 and counts[key, 'play'] > 0, f'Missing visible hold/play evidence for {key}'
    assert any(pose.get('weapon_visible') for frame in frames for pose in frame['poses'] if pose['pose']['key'] == 'action_pistol'), 'Original ranged weapon was not attached'
    intervals = []
    with (directory/'video.ffconcat').open('w') as listing:
        listing.write('ffconcat version 1.0\n')
        for index, frame in enumerate(frames):
            assert re.fullmatch(r'frames/[0-9]+\.jpg', frame['file'])
            assert (directory/frame['file']).is_file()
            duration = frames[index+1]['seconds']-frame['seconds'] if index+1<len(frames) else .05
            assert 0 < duration < 2, duration
            intervals.append(duration)
            listing.write(f"file '{frame['file']}'\nduration {duration:.6f}\n")
        listing.write(f"file '{frames[-1]['file']}'\n")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    command = ['ffmpeg', '-hide_banner', '-y', '-f', 'concat', '-safe', '1', '-i', str(directory/'video.ffconcat'),
               '-i', str(directory/'combat-audio.wav'), '-vf', 'fps=30,format=yuv420p',
               '-af', f"atrim=start={frames[0]['seconds']:.6f},asetpts=PTS-STARTPTS",
               '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-c:a', 'aac', '-b:a', '192k',
               '-shortest', '-movflags', '+faststart', str(args.out.resolve())]
    subprocess.run(command, check=True)
    probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(args.out)]))
    assert {'audio', 'video'} <= {s['codec_type'] for s in probe['streams']}
    assert abs(float(probe['format']['duration'])-sum(intervals)) < .2
    result = dict(video=str(args.out.resolve()), frames=len(frames), duration=float(probe['format']['duration']),
                  max_capture_interval=max(intervals), audio='Godot master bus; no microphone or desktop audio',
                  renderer='Forward+ Vulkan', headset_tested=False, server_mocked=False,
                  remote_server=evidence.get('remote_server',False), required_pose_roles=args.required_roles,
                  pose_samples={key+':'+phase:count for (key,phase),count in sorted(counts.items())})
    args.out.with_suffix('.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
