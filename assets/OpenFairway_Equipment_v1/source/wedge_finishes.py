"""Plain wedge metals: solid colors, without badges, text or decorative graphics.

The four-region atlas remains compatible with the fitted heads. Only the striking
face's normal map retains its functional grooves. Condition uniformly dulls the
finish; it does not reveal decorative patterns. Rusty Gap uses the head-specific
bake from tools/bake_rusty_wedge.py, including its neck UVs. All loaners match.
"""
from pathlib import Path
import io
import os
import shutil

import numpy as np
from PIL import Image

S, T = 1024, 512
# Solid head color, roughness, metallic. No contrasting face or accent color.
FINISHES = {
    'loaner_pw': ('#99a3a6', .50, .70),      # matching satin silver loaners
    'loaner_gw': ('#99a3a6', .50, .70),
    'loaner_sw': ('#99a3a6', .50, .70),
    'loaner_lw': ('#99a3a6', .50, .70),
    'grocery_pw': ('#55595a', .76, .24),     # matte charcoal
    'bent_neck_pw': ('#455f78', .43, .70),   # blue steel
    'flop_master_60': ('#141619', .32, .65), # black oxide
    'raw_face_56': ('#e4e8eb', .19, .95),    # bright polished silver
    'tour_grind_58': ('#e0ae3c', .29, .88),  # polished yellow gold
    'sand_shovel': ('#77583d', .58, .55),    # dark bronze
}


def save(image, path):
    buffer = io.BytesIO()
    image.save(buffer, format='PNG', compress_level=6)
    temporary = path.with_suffix('.png.tmp')
    temporary.write_bytes(buffer.getvalue())
    os.replace(temporary, path)


def make_wedge(item, output):
    asset_id = item['id']
    destination = Path(output) / asset_id
    destination.mkdir(parents=True, exist_ok=True)
    if asset_id == 'rusty_gap_52':
        baked = Path(__file__).parent / 'materials' / asset_id / 'baked'
        result = {}
        for kind in ('albedo', 'orm', 'normal', 'wear'):
            filename = f'ofg_{asset_id}_{kind}.png'
            if not (baked / filename).is_file():
                raise FileNotFoundError('Bake Rusty Gap with tools/bake_rusty_wedge.py first')
            shutil.copyfile(baked / filename, destination / filename)
            result[kind] = f'{asset_id}/{filename}'
        return result
    color, roughness, metallic = FINISHES[asset_id]
    normal = Image.new('RGB', (S, S), (128, 128, 255))
    yy, xx = np.mgrid[:T, :T]
    groove = ((np.mod(yy - 51, 36) < 2) & (xx > 58) & (xx < 454) &
              (yy > 58) & (yy < 446))
    height = groove.astype(float) * -.7
    gy, gx = np.gradient(height)
    directions = np.stack((-gx, gy, np.ones_like(height)), -1)
    directions /= np.linalg.norm(directions, axis=2)[..., None]
    normal.paste(Image.fromarray(np.uint8((directions * .5 + .5) * 255)), (T, 0))
    maps = {
        'albedo': Image.new('RGB', (S, S), color),
        'orm': Image.new('RGB', (S, S), (255, round(roughness * 255), round(metallic * 255))),
        'normal': normal,
        'wear': Image.new('RGB', (S, S), (42, 0, 0)),
    }
    result = {}
    for kind, image in maps.items():
        filename = f'ofg_{asset_id}_{kind}.png'
        save(image, destination / filename)
        result[kind] = f'{asset_id}/{filename}'
    return result
