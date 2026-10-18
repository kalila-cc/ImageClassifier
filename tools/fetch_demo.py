"""Download public sample images for the visual prototype, never user media."""
from pathlib import Path
from urllib.request import urlopen, Request
from concurrent.futures import ThreadPoolExecutor
ROOT = Path(__file__).resolve().parents[1] / 'ui' / 'assets'
ROOT.mkdir(parents=True, exist_ok=True)
IDS = [1015, 1016, 1039, 1043, 1040, 1036, 1020, 1024, 1025, 1041, 1042, 1050]
def fetch(item):
    i, photo_id = item
    dest = ROOT / f'photo-{i:02}.jpg'
    if dest.exists(): return dest.name
    req = Request(f'https://picsum.photos/id/{photo_id}/900/650', headers={'User-Agent': 'ImageClassifier-UI-Preview'})
    with urlopen(req, timeout=40) as response: dest.write_bytes(response.read())
    return dest.name
with ThreadPoolExecutor(max_workers=4) as executor:
    for result in executor.map(fetch, enumerate(IDS)): print(result)
