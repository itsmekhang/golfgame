"""Replace embedded club texture PNGs in a GLB without touching its geometry.

Usage: python tools/update_club_texture_images.py MODEL.glb TEXTURE_DIRECTORY
All non-image buffer views, node transforms, materials, and mesh metadata survive
byte-for-byte. The source atlas PNGs also remain the runtime shader's inputs.
"""
import argparse
import json
from pathlib import Path
import struct


def update(model, texture_dir):
    original = model.read_bytes()
    magic, version, total = struct.unpack_from('<III', original)
    assert magic == 0x46546C67 and version == 2 and total == len(original)
    offset, document, binary = 12, None, None
    while offset < total:
        length, kind = struct.unpack_from('<II', original, offset)
        payload = original[offset+8:offset+8+length]
        if kind == 0x4E4F534A:
            document = json.loads(payload)
        elif kind == 0x004E4942:
            binary = payload
        offset += 8 + length
    assert document is not None and binary is not None
    replacements = {}
    for image in document.get('images', []):
        path = texture_dir / (image.get('name', '') + '.png')
        if path.is_file() and 'bufferView' in image:
            replacements[image['bufferView']] = path.read_bytes()
            print('Embedded', path.name)
    if not replacements:
        raise ValueError('No embedded image names match the supplied texture directory')
    result = bytearray()
    for index, view in enumerate(document['bufferViews']):
        assert view.get('buffer', 0) == 0
        start = view.get('byteOffset', 0)
        old = binary[start:start+view['byteLength']]
        data = replacements.get(index, old)
        result.extend(b'\0' * (-len(result) % 4))
        view['byteOffset'], view['byteLength'] = len(result), len(data)
        result.extend(data)
        if index not in replacements:
            assert result[view['byteOffset']:view['byteOffset']+view['byteLength']] == old
    document['buffers'][0]['byteLength'] = len(result)
    result.extend(b'\0' * (-len(result) % 4))
    encoded = json.dumps(document, separators=(',', ':')).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    output = struct.pack('<III', magic, version, 28 + len(encoded) + len(result))
    output += struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
    output += struct.pack('<II', len(result), 0x004E4942) + result
    temporary = model.with_suffix('.glb.tmp')
    temporary.write_bytes(output)
    temporary.replace(model)
    print('Updated images; preserved geometry:', model)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', type=Path)
    parser.add_argument('texture_dir', type=Path)
    args = parser.parse_args()
    update(args.model, args.texture_dir)
