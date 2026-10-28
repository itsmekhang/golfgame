"""A clip for the restaurant's bar TV, from the user's GIF -> a sheet of its frames
(assets/facilities/props/tv_clip.jpg) that FacilityBuilder plays on the screen.

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_tv_clip.py -- <clip.gif>

Blender's sequencer reads the GIF (ffmpeg) and renders each frame at FRAME size; they're laid
left to right, top to bottom, COLS to a row, into one JPEG. Prints the frame count and rate,
which FacilityBuilder.TV_CLIP must match.
"""
import math
import struct
import os
import sys
import tempfile

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "tv_clip.jpg")
FRAME = (240, 133)  # each frame (px): the GIF's 400 x 221 at 60%
COLS = 12
RATE = (100, 7.0)  # the scene's frame rate, fps / fps_base: the GIF's own (a frame every 7 cs), so
# the sequencer takes its frames one for one


def main():
    src = sys.argv[sys.argv.index("--") + 1]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps, sc.render.fps_base = RATE
    sc.view_settings.view_transform = "Standard"  # the clip's colours as they are (not AgX's, once rendering, again saving)
    sc.view_settings.look = "None"
    # rendered one for one at the GIF's own size (set before the strip goes in: the sequencer sizes
    # a strip to the canvas it's added to, so any other size crops it), shrunk to FRAME after
    with open(src, "rb") as f:
        size = struct.unpack("<HH", f.read(10)[6:10])
    sc.render.resolution_x, sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    se = sc.sequence_editor_create()
    strips = se.strips if hasattr(se, "strips") else se.sequences
    clip = strips.new_movie("clip", src, 1, 1, fit_method="ORIGINAL")
    n = int(clip.frame_final_duration)
    sc.frame_start, sc.frame_end = 1, n
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    tmp = tempfile.mkdtemp(prefix="tv_clip_")
    sc.render.filepath = os.path.join(tmp, "f_")
    bpy.ops.render.render(animation=True)
    rows = math.ceil(n / COLS)
    w, h = FRAME
    sheet = np.zeros((rows * h, COLS * w, 4), dtype=np.float32)
    sheet[..., 3] = 1.0
    for i in range(n):
        im = bpy.data.images.load(os.path.join(tmp, "f_%04d.png" % (i + 1)))
        im.scale(w, h)
        px = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        bpy.data.images.remove(im)
        r, c = i // COLS, i % COLS
        # Blender's pixels run bottom up: frame 0 at the sheet's top left (its last rows)
        y0 = (rows - 1 - r) * h
        sheet[y0:y0 + h, c * w:(c + 1) * w] = px.reshape(h, w, 4)
    out = bpy.data.images.new("tv_clip", COLS * w, rows * h, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = OUT
    out.file_format = "JPEG"
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = 88
    out.save_render(OUT, scene=sc)
    print("TV_CLIP frames %d cols %d rows %d frame %dx%d fps %.4f -> %s (%d bytes)" % (n, COLS, rows, w, h, sc.render.fps / sc.render.fps_base, OUT, os.path.getsize(OUT)))


main()
