"""A video for a bar TV, from the user's MP4 -> an Ogg Theora file (Godot plays Theora, not MP4)
that FacilityBuilder plays on the screen: assets/facilities/props/tv_video.ogv (the second TV), or
--out's (tv_golf.ogv: the first TV's golf).

    blender -b --factory-startup --disable-autoexec -P tools/blender/import_tv_video.py -- <video.mp4> [--out <project path>] [--width <px>]

Blender's sequencer reads the video (ffmpeg) at its own size and frame rate -- set before the strip
goes in, so it isn't cropped -- and writes it SCALE of that (or `--width` px across, fitted),
without its sound (a TV over the bar).
"""
import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "facilities", "props", "tv_video.ogv")
SCALE = 25  # % of the video's size: 1920 x 1080 -> 480 x 270, plenty for a 1 m screen
BITRATE = 900  # kb/s


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src = argv[0]
    out = os.path.join(ROOT, argv[argv.index("--out") + 1]) if "--out" in argv else OUT
    width = int(argv[argv.index("--width") + 1]) if "--width" in argv else 0
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    probe = bpy.data.movieclips.load(src)
    w, h, fps, n = probe.size[0], probe.size[1], probe.fps, probe.frame_duration
    bpy.data.movieclips.remove(probe)
    if width:
        # that wide, its height to match (even, for Theora); the strip fitted into it
        sc.render.resolution_x, sc.render.resolution_y = width, round(h * width / w / 2) * 2
        sc.render.resolution_percentage = 100
    else:
        sc.render.resolution_x, sc.render.resolution_y = w, h
        sc.render.resolution_percentage = SCALE
    sc.render.fps, sc.render.fps_base = round(fps), round(fps) / fps
    sc.view_settings.view_transform = "Standard"  # its colours as they are
    sc.view_settings.look = "None"
    se = sc.sequence_editor_create()
    strips = se.strips if hasattr(se, "strips") else se.sequences
    clip = strips.new_movie("clip", src, 1, 1, fit_method="FIT" if width else "ORIGINAL")
    sc.frame_start, sc.frame_end = 1, int(clip.frame_final_duration)
    im = sc.render.image_settings
    if hasattr(im, "media_type"):
        im.media_type = "VIDEO"
    im.file_format = "FFMPEG"
    ff = sc.render.ffmpeg
    ff.format = "OGG"
    ff.codec = "THEORA"
    ff.audio_codec = "NONE"
    ff.constant_rate_factor = "NONE"
    ff.video_bitrate = BITRATE
    ff.gopsize = round(fps)
    sc.render.filepath = out
    sc.render.use_file_extension = False
    bpy.ops.render.render(animation=True)
    size = (sc.render.resolution_x * sc.render.resolution_percentage // 100, sc.render.resolution_y * sc.render.resolution_percentage // 100)
    print("TV_VIDEO %dx%d at %.2f fps, %d frames (%.1f s) -> %s (%d bytes)" % (size[0], size[1], fps, sc.frame_end, sc.frame_end / fps, out, os.path.getsize(out)))


main()
