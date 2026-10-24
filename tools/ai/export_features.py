"""One-time developer export. The shipped inference runtime does not need torch."""
import argparse
from pathlib import Path
import os

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
args = parser.parse_args()
os.environ['HF_HOME'] = str(args.root / 'export-cache')
import torch
from transformers import Dinov2Model

torch.set_num_threads(4)
model = Dinov2Model.from_pretrained('facebook/dinov2-small',
    revision='ed25f3a31f01632728cabb09d1542f84ab7b0056', attn_implementation='eager')

class Features(torch.nn.Module):
    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone
    def forward(self, image):
        features = self.backbone(pixel_values=image).last_hidden_state[:, 0]
        return torch.nn.functional.normalize(features, dim=-1)

output = args.root / 'models' / 'features.onnx'
temporary = output.with_suffix('.partial')
with torch.no_grad():
    torch.onnx.export(Features(model.eval()), torch.zeros(1, 3, 224, 224), str(temporary),
                      input_names=['image'], output_names=['features'], opset_version=17,
                      do_constant_folding=True)
temporary.replace(output)
print(f'Exported {output.stat().st_size} bytes', flush=True)
