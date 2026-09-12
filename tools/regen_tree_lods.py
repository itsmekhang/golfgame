"""Regenerate the tree LOD meshes we ship with fuller crowns.

The pack's own LOD rule thins the crown by dropping leaves (LOD1 keeps ~1/6 of them,
LOD2 ~1/56) while barely enlarging the survivors, so distant trees read as bare.
This drives the pack's generator (assets/high fidelity assets/.../source) with a
"fewer but bigger" rule instead: LOD1 keeps ~1/4 of the leaves at 1.9x, LOD2 ~1/11
at 3.2x (coverage stays close to the full crown), pines get fatter needle tufts.
Only the species ForestPlanter uses are rebuilt, straight into assets/nature_pack.

Run: python tools/regen_tree_lods.py
"""
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "high fidelity assets", "Golf_Nature_Pack", "source")
OUT = os.path.join(ROOT, "nature_pack", "models", "trees", "lod")
sys.path.insert(0, SRC)

# every species, every A/B/C variant
SPECIES = {name: [0, 1, 2] for name in [
    "loblolly_pine", "longleaf_pine", "eastern_white_pine", "live_oak", "white_oak", "red_maple",
    "sweetgum", "tulip_poplar", "southern_magnolia", "river_birch", "bald_cypress", "weeping_willow",
    "eastern_red_cedar", "flowering_dogwood_white", "flowering_dogwood_pink", "crape_myrtle"]}

# Patch the generator's LOD rules in source form, then load it as a module.
code = open(os.path.join(SRC, "realvegetation.py")).read()
patches = [
    ("active=(detail==0 or (t%3==0 if detail==1 else t%7==0)) and (detail<2 or s%2==0)",
     "active=(detail==0 or (t%2==0 if detail==1 else t%3==0)) and (detail<2 or s%2==0)"),
    ("keep=active and (detail==0 or k%2==0) and (detail<2 or k%4==0)",
     "keep=active and (detail==0 or k%2==0)"),
    ("items.append((leafbase,d,leaflen*(1+detail*.16),width*(1+detail*.16),col,roll,.95))",
     "items.append((leafbase,d,leaflen*LEAF_GROW[detail],width*LEAF_GROW[detail],col,roll,.95))"),
    ("active=detail==0 or (s%2==0 if detail==1 else s%4==0)",
     "active=detail==0 or s%2==0"),
    ("needles.append((pos,axis,length*(1+detail*.15),(.0055 if not fine else .018)*(1+detail*.2),P['pine']*rng.uniform(.80,1.22),angle,.95))",
     "needles.append((pos,axis,length*NEEDLE_GROW[detail],(.0055 if not fine else .018)*NEEDLE_WIDTH_GROW[detail],P['pine']*rng.uniform(.80,1.22),angle,.95))"),
]
for old, new in patches:
    assert old in code, "generator source changed; patch not found: " + old[:60]
    code = code.replace(old, new)
code = "LEAF_GROW=[1.0,1.9,3.2]\nNEEDLE_GROW=[1.0,1.7,2.8]\nNEEDLE_WIDTH_GROW=[1.0,2.6,5.0]\n" + code
spec = importlib.util.spec_from_loader("fullveg", loader=None)
fullveg = importlib.util.module_from_spec(spec)
fullveg.__file__ = os.path.join(SRC, "realvegetation.py")
exec(compile(code, fullveg.__file__, "exec"), fullveg.__dict__)

os.makedirs(OUT, exist_ok=True)
for name, variants in SPECIES.items():
    for v in variants:
        vid = f"{name}_{'ABC'[v]}"
        for detail in (1, 2):
            m = fullveg.tree(name, v, detail)
            path = os.path.join(OUT, f"{vid}_LOD{detail}.glb")
            m.export(path, {"lod": detail, "asset": vid, "note": "fuller-crown LOD from tools/regen_tree_lods.py"})
            print(f"{vid} LOD{detail}: {m.triangles:,} tris, {m.leaf_count} leaves, {m.needle_count} needles", flush=True)
print("done")
