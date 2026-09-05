# Convert Real-ESRGAN realesr-general-x4v3 (+ wdn variant) .pth weights to ncnn
# param/bin via pnnx. Also emits a 0.5 weight-space blend, which is exactly what
# Real-ESRGAN's `-dn 0.5` option does at inference time.
import sys, os, torch, torch.nn as nn, torch.nn.functional as F

class SRVGGNetCompact(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=32, upscale=4):
        super().__init__()
        self.upscale = upscale
        self.body = nn.ModuleList()
        self.body.append(nn.Conv2d(num_in_ch, num_feat, 3, 1, 1))
        self.body.append(nn.PReLU(num_parameters=num_feat))
        for _ in range(num_conv):
            self.body.append(nn.Conv2d(num_feat, num_feat, 3, 1, 1))
            self.body.append(nn.PReLU(num_parameters=num_feat))
        self.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.upsampler = nn.PixelShuffle(upscale)
    def forward(self, x):
        out = x
        for m in self.body:
            out = m(out)
        out = self.upsampler(out)
        base = F.interpolate(x, scale_factor=self.upscale, mode='nearest')
        return out + base

def load_sd(p):
    d = torch.load(p, map_location='cpu', weights_only=False)
    return d['params_ema'] if 'params_ema' in d else d['params']

sd_a = load_sd('realesr-general-x4v3.pth')
sd_b = load_sd('realesr-general-wdn-x4v3.pth')
convs = [k for k in sd_a if k.startswith('body.') and k.endswith('.weight') and sd_a[k].dim() == 4]
num_conv = len(convs) - 2
print('num_conv', num_conv, 'feat', sd_a['body.0.weight'].shape[0])

import pnnx
for name, sd in [('general-x4v3-dn0', sd_a),
                 ('general-x4v3-dn05', {k: (sd_a[k] * 0.5 + sd_b[k] * 0.5) for k in sd_a}),
                 ('general-x4v3-dn1', sd_b)]:
    m = SRVGGNetCompact(num_conv=num_conv)
    m.load_state_dict(sd, strict=True)
    m.eval()
    x = torch.rand(1, 3, 64, 64)
    with torch.no_grad():
        y = m(x)
    print(name, 'out', tuple(y.shape))
    os.makedirs(name, exist_ok=True)
    pnnx.export(m, os.path.join(name, name + '.pt'), x)
    print('exported', name, os.listdir(name))
