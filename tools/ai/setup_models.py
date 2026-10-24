"""Prepare versioned local inference assets; no user images leave the computer."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import urllib.request
import zipfile

MODEL_RELEASE = 'cd4d709'
FILES = {
    'person': 'rtmposev1/onnx_sdk/yolox_m_8xb8-300e_humanart-c2c7a14a.zip',
    'pose': 'rtmposev1/onnx_sdk/rtmpose-l_simcc-body7_pt-body7_420e-384x288-3f5a1437_20230504.zip',
}
HASHES = {
    'person': '3dea6513388889f0fff4b77bf7a26013600321b9eb9ceb0e9a400a82572f5f23',
    'pose': '62425affc6b9edba8f8a65f55f5e278fec5d905d0c90578e0f8503bdf3954587',
}

def verify_hash(path, name):
    if hashlib.sha256(path.read_bytes()).hexdigest() != HASHES[name]:
        raise ValueError(f'Model checksum mismatch: {name}; remove the damaged file and run setup again')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--check-features', action='store_true')
    args = parser.parse_args()
    models = args.root / 'models'
    models.mkdir(parents=True, exist_ok=True)
    if args.check_features:
        import onnxruntime as ort
        ort.InferenceSession(str(models / 'features.onnx'), providers=['CPUExecutionProvider'])
        return
    if not args.verify:
        for name, remote in FILES.items():
            target = models / (name + '.onnx')
            if target.exists():
                try:
                    verify_hash(target, name)
                    continue
                except ValueError:
                    target.unlink()  # Explicit installation retries replace damaged model assets only.
            partial = target.with_suffix('.partial')
            # Reuse the already verified research assets on this workstation.
            local = args.root.parent / 'crop-research' / (name + '.onnx')
            if local.exists():
                verify_hash(local, name)
                shutil.copyfile(local, partial)
                partial.replace(target)
                continue
            archive = models / (name + '.download')
            url = f'https://huggingface.co/Tau-J/RTMPose/resolve/{MODEL_RELEASE}/{remote}'
            with urllib.request.urlopen(url, timeout=90) as response, archive.open('wb') as dest:
                shutil.copyfileobj(response, dest)
            with zipfile.ZipFile(archive) as z:
                entries = [n for n in z.namelist() if n.endswith('.onnx')]
                if len(entries) != 1:
                    raise ValueError('Unexpected model archive')
                with z.open(entries[0]) as source, partial.open('wb') as dest:
                    shutil.copyfileobj(source, dest)
            verify_hash(partial, name)
            partial.replace(target)
            archive.unlink()
        return
    import onnxruntime as ort
    report = {'schema': 1, 'models': {}}
    for name in ('person', 'pose', 'features'):
        path = models / (name + '.onnx')
        if name in HASHES: verify_hash(path, name)
        session = ort.InferenceSession(str(path), providers=['CPUExecutionProvider'])
        report['models'][name] = {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                                  'inputs': [x.name for x in session.get_inputs()]}
    temporary = models / 'manifest.partial'
    temporary.write_text(json.dumps(report, indent=2), encoding='utf-8')
    temporary.replace(models / 'manifest.json')
    print(json.dumps(report), flush=True)

if __name__ == '__main__':
    main()
