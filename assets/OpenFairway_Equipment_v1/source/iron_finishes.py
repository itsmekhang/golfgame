"""Solid iron finishes with small, original geometric emblems on the backs."""
from pathlib import Path
import hashlib
import math
import numpy as np
from PIL import Image, ImageDraw


BACK_DESIGNS = {
    'loaner_irons': 'stepping diamonds',
    'thrift_cavity_backs': 'nested hexagons',
    'mustard_muscle': 'sunburst',
    'game_improver_xl': 'double chevrons',
    'blade_runner_forged': 'three blades',
    'tour_forged_cb': 'faceted diamond',
    'combo_proto': 'orbital bolt',
}


def back_emblem(asset_id):
    """Paint only the rear atlas tile; all other head surfaces keep their base.

    The fitted head UVs project this tile from the inspector's rear angle.
    Supersampling keeps the small polygons and rings clean in close-up views.
    """
    scale = 4
    tile = Image.new('RGBA', (512 * scale, 512 * scale))
    draw = ImageDraw.Draw(tile)
    cx, cy = 300, 230

    def points(vertices):
        return [((cx + x) * scale, (cy + y) * scale) for x, y in vertices]

    def polygon(vertices, color):
        draw.polygon(points(vertices), fill=color)

    def line(vertices, color, width=5):
        draw.line(points(vertices), fill=color, width=width * scale, joint='curve')

    def ellipse(box, color, width=0):
        x0, y0, x1, y1 = box
        box = ((cx + x0) * scale, (cy + y0) * scale,
               (cx + x1) * scale, (cy + y1) * scale)
        draw.ellipse(box, fill=color if not width else None,
                     outline=color if width else None, width=max(1, width * scale))

    def ring(vertices, color, width=5):
        line(vertices + vertices[:1], color, width)

    if asset_id == 'loaner_irons':
        for x, y, size, color in [(-50, 18, 18, '#254d4b'),
                                  (0, 0, 25, '#255a58'),
                                  (55, -18, 31, '#d5f2cc')]:
            polygon([(x, y-size), (x+size, y), (x, y+size), (x-size, y)], color)
    elif asset_id == 'thrift_cavity_backs':
        for radius, color in [(53, '#704838'), (34, '#357d78')]:
            hexagon = [(math.cos(i * math.tau / 6) * radius,
                        math.sin(i * math.tau / 6) * radius) for i in range(6)]
            ring(hexagon, color, 7)
        ellipse((-8, -8, 8, 8), '#704838')
        for x in (-76, 76):
            ellipse((x-5, -5, x+5, 5), '#357d78')
    elif asset_id == 'mustard_muscle':
        star = []
        for i in range(16):
            angle = i * math.pi / 8 - math.pi / 2
            radius = 58 if i % 2 == 0 else 27
            star.append((math.cos(angle) * radius, math.sin(angle) * radius))
        polygon(star, '#f4deb1')
        ellipse((-20, -20, 20, 20), '#51412c')
        ellipse((-8, -8, 8, 8), '#f4deb1')
    elif asset_id == 'game_improver_xl':
        for x, color in [(-50, '#d15b41'), (8, '#325568')]:
            polygon([(x-22, -49), (x+12, -49), (x+48, 0),
                     (x+12, 49), (x-22, 49), (x+13, 0)], color)
        ellipse((73, -7, 87, 7), '#d15b41')
    elif asset_id == 'blade_runner_forged':
        for x, height in [(-52, 32), (-8, 47), (36, 62)]:
            polygon([(x-17, height), (x+8, -height),
                     (x+29, -height), (x+4, height)], '#263e43')
        polygon([(78, 32), (86, 42), (78, 52), (70, 42)], '#46b7a7')
    elif asset_id == 'tour_forged_cb':
        ring([(0, -58), (61, -15), (0, 58), (-61, -15)], '#e2be76', 7)
        line([(-61, -15), (61, -15)], '#e2be76', 5)
        line([(-28, -35), (0, 58), (28, -35)], '#e2be76', 5)
        for x in (-81, 81):
            ellipse((x-5, 17, x+5, 27), '#e2be76')
    elif asset_id == 'combo_proto':
        ellipse((-68, -49, 68, 49), '#58d6d2', 6)
        polygon([(8, -64), (-31, 7), (-5, 7), (-15, 62),
                 (39, -15), (10, -15), (29, -64)], '#f2a663')
        ellipse((-72, -6, -55, 11), '#f2a663')
        polygon([(57, -49), (69, -37), (57, -25), (45, -37)], '#e9edce')
    else:
        raise ValueError(f'Missing rear emblem for iron {asset_id}')
    return tile.resize((512, 512), Image.Resampling.LANCZOS)


def make_iron(item, output):
    asset_id = item['id']
    destination = Path(output) / asset_id
    destination.mkdir(parents=True, exist_ok=True)
    color = tuple(int(item['crown'][i:i + 2], 16) for i in (1, 3, 5))
    roughness = .52 if item['style'] in ('rental', 'cavity') else .36
    maps = {
        'albedo': Image.new('RGB', (1024, 1024), color),
        'orm': Image.new('RGB', (1024, 1024), (255, round(roughness * 255), 230)),
        'normal': Image.new('RGB', (1024, 1024), (128, 128, 255)),
    }
    emblem = back_emblem(asset_id)
    maps['albedo'].paste(emblem, (512, 512), emblem)
    # Keep the same deterministic wear layout used by the condition shader.
    # The face's score lines remain mesh geometry with the same solid color.
    rng = np.random.default_rng(int(hashlib.sha256(asset_id.encode()).hexdigest()[:8], 16))

    def noise(size):
        im = Image.fromarray(rng.integers(0, 256, (size, size), dtype=np.uint8))
        return np.asarray(im.resize((512, 512), Image.Resampling.BICUBIC), dtype=float) / 255

    low, fine = noise(26), noise(160)
    yy, xx = np.mgrid[0:512, 0:512].astype(float)
    edge = np.clip((np.maximum(abs(xx / 512 - .5), abs(yy / 512 - .5)) - .36) * 7, 0, 1)
    dirt = np.clip(low * .66 + edge * .42, 0, 1)
    chips = np.clip((fine - .44) * 2.5, 0, 1) * edge
    oxidation = np.clip((low - .37) * 1.7, 0, 1) * (edge * .7 + .12)
    wear = Image.new('RGB', (1024, 1024))
    for q in range(4):
        tile = Image.fromarray(np.uint8(np.stack([dirt, chips, oxidation], axis=2) * 255))
        draw = ImageDraw.Draw(tile)
        for _ in range(22):
            sx, sy, dx = int(rng.integers(18, 494)), int(rng.integers(18, 494)), int(rng.integers(7, 48))
            draw.line((sx, sy, sx + dx, sy - int(rng.integers(1, 8))),
                      fill=(110, 180, 36), width=int(rng.integers(1, 3)))
        wear.paste(tile, ((q % 2) * 512, (q // 2) * 512))
    maps['wear'] = wear
    result = {}
    for kind, image in maps.items():
        path = destination / f'ofg_{asset_id}_{kind}.png'
        image.save(path, compress_level=6)
        result[kind] = f'{asset_id}/{path.name}'
    return result
