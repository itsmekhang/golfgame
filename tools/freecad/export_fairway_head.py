"""Export the fairway wood heads (FreeCAD) as the game's fairway woods, one livery per club.

Three heads of their own (Documents/FreeCAD/GolfHead/fairway/fairway_params.py, FAIRWAY_STYLE), built by
the driver's pipeline (driver/build_hybrid_driver.py with HEAD_PARAMS) into fairway/<style>/*.brep:

  modern   a pear-shaped, low, flat-soled 3 wood with a speed slot and twin rails: the rental 3 and 5
           woods, the Garage Sale 3 wood, the Lowball 5 wood
  tour     a compact small head with the slot and a weight port low at the back: the Tour Spoon 13
  classic  a rounder, deeper-faced pear with a smooth sole: the Steelhead Classic, the Heirloom 5 wood

Each goes through the driver's exporter (tools/freecad/export_driver_460_head.py) with its source, art
(tools/make_fairway_textures.py, assets/Fairway_Wood_V2/textures), crown/sole parting line, face band
(RIM: a wide cup-face band on the modern and tour heads, after the hybrid), mouth height and its clubs'
liveries (FAIRWAY_LIVERIES), to assets/Selected_Club_Heads/skins/<club>_fw_base.glb.

    freecadcmd -c "exec(open(r'C:/Users/willi/Documents/GolfGame/tools/freecad/export_fairway_head.py').read())"
FAIRWAY_STAGE=masks first writes each head's crown/sole masks the art is drawn on (then python
tools/make_fairway_textures.py, then this again).
"""
import os

GAME = r"C:/Users/willi/Documents/GolfGame"
SRC = r"C:/Users/willi/Documents/FreeCAD/GolfHead/fairway"
TEX = os.path.join(GAME, "assets", "Fairway_Wood_V2", "textures")
BOX = "-66,52,-8,100"     # the art's frame (tools/make_fairway_textures.py BOX)
STYLES = {  # head: its clubs, crown/sole parting height, face band, mouth height (mm)
    "modern": dict(clubs="loaner_3w,loaner_5w,garage_3w,lowball_5w", z_part=13.6, rim=10.0, mouth=61.3),
    "tour": dict(clubs="tour_spoon", z_part=13.8, rim=10.0, mouth=61.3),
    "classic": dict(clubs="steelhead_classic,heirloom_5w", z_part=16.0, rim=3.0, mouth=61.3),
}
EXPORTER = os.path.join(GAME, "tools", "freecad", "export_driver_460_head.py")
MASKS = os.path.join(GAME, "tools", "freecad", "driver_460_masks.py")
for style, spec in STYLES.items():
    if os.environ.get("FAIRWAY_ONLY") and style not in os.environ["FAIRWAY_ONLY"].split(","):
        continue
    os.environ.update({
        "DRIVER_SRC": SRC + "/" + style, "DRIVER_TEX_DIR": TEX, "DRIVER_LIVERY_SET": "fairway",
        "FAIRWAY_CLUBS": spec["clubs"], "DRIVER_SKIN_SUFFIX": "_fw", "DRIVER_Z_PART": str(spec["z_part"]),
        "DRIVER_RIM": str(spec["rim"]),
        "DRIVER_MOUTH_Z": os.environ.get("FAIRWAY_MOUTH_" + style.upper(), str(spec["mouth"])),
    })
    print("[%s]" % style)
    if os.environ.get("FAIRWAY_STAGE") == "masks":
        os.environ["MASK_DIR"] = os.path.join(TEX, "masks_" + style)
        os.environ["MASK_BOX"] = BOX
        exec(open(MASKS, encoding="utf-8").read(), {"__name__": "masks_" + style})
    else:
        exec(open(EXPORTER, encoding="utf-8").read(), {"__name__": "export_" + style})
