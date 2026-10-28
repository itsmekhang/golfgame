"""Where the Driver460 head's crown paint and sole art land in their textures, for the livery art.

    freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/driver_460_masks.py').read())"

Runs the exporter's own zoning (tools/freecad/export_driver_460_head.py: the body cut along its crown,
sole, metal and flat-face boundaries) and rasterises the crown and sole triangles as seen from above,
in the textures' frame (BOX, PPM from tools/make_driver_textures.py), to
assets/Driver_460_Head/textures/masks/{crown,sole}_mask.png (white where the art shows). The texture
generator draws its trim lines, panels and fades from these, so they follow the head's real outline.
"""
import os

GAME = r"C:/Users/willi/Documents/GolfGame"
OUT = os.environ.get("MASK_DIR", os.path.join(GAME, "assets", "Driver_460_Head", "textures", "masks"))
BOX = tuple(float(v) for v in os.environ.get("MASK_BOX", "-76,60,-8,116").split(","))  # (the fairway's: its own)
PPM = 10.0


def main():
    import numpy as np
    os.environ["DRIVER_EXPORT_NO_MAIN"] = "1"
    ex = {"__name__": "export_driver_460_head"}
    with open(os.path.join(GAME, "tools", "freecad", "export_driver_460_head.py"), encoding="utf-8") as f:
        exec(f.read(), ex)
    import Part
    parts = ex["load_parts"]()
    top, _ = ex["hosel_top"](parts["Ferrule"])
    sphere = next(f.Surface for f in parts["FaceInsert"].Faces if isinstance(f.Surface, Part.Sphere))
    solids = [s for p in parts.values() for s in p.Solids]
    faces, _ = ex["visible_faces"]({"Body": parts["Body"]}, solids, top)
    pts, tris = ex["mesh"](faces["Body"], ex["DEFLECTION"]["Body"])
    pos, nrm, tri = ex["creased"](pts, tris)
    pos, nrm, tri, slot = ex["body_slots"](pos, nrm, tri, sphere.Center, sphere.Radius, top)
    from PIL import Image, ImageDraw
    x0, x1, y0, y1 = BOX
    size = (round((x1 - x0) * PPM), round((y1 - y0) * PPM))
    os.makedirs(OUT, exist_ok=True)
    for name in ("crown", "sole"):
        img = Image.new("L", size, 0)
        d = ImageDraw.Draw(img)
        for t in tri[slot == name]:
            d.polygon([((pos[i, 0] - x0) * PPM, (pos[i, 1] - y0) * PPM) for i in t], fill=255)
        img.save(os.path.join(OUT, name + "_mask.png"))
        print(name, "mask", size, "px:", int((np.array(img) > 0).sum()))


main()
