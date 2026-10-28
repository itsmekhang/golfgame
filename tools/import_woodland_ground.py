"""Import the supplied grass PBR pack without brightness normalization.

009: rough; 002: first cut; 001: fringe/tee turf; 005: woodland litter.
256px maps with prefiltering and softer albedo contrast reduce distant speckling.
"""
from pathlib import Path
from PIL import Image, ImageFilter, ImageStat

source = Path.home() / 'Downloads/Grass Textures (1)'
target = Path(__file__).resolve().parents[1] / 'assets/textures/tiles/woodland_ground'
target.mkdir(parents=True, exist_ok=True)
maps = {'albedo': 'Diffuse', 'normal': 'Normal', 'roughness': 'Roughness', 'ao': 'Ambient Occlusion'}
for variant in ['001', '002', '005', '007', '009']:
    for suffix, source_suffix in maps.items():
        path = source / ('Grass' + variant) / '2k' / ('Grass' + variant + '_' + source_suffix + '.png')
        # BOX averages fine blades without sharpening/ringing. Soften the small
        # remaining flecks instead of turning them into high-contrast pixels.
        im = Image.open(path).convert('RGB').resize((256, 256), Image.Resampling.BOX)
        im = im.filter(ImageFilter.GaussianBlur(0.7))
        if suffix == 'albedo':
            mean = tuple(round(v) for v in ImageStat.Stat(im).mean)
            im = Image.blend(Image.new('RGB', im.size, mean), im, 0.55)
        im.save(target / ('grass_' + variant + '_' + suffix + '.png'))
print('Imported woodland ground maps:', target)
