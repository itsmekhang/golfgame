"""Tileable brushed-stainless textures (albedo + glTF metallic-roughness), made with numpy/PIL."""
import io
import numpy as np
from PIL import Image


def _smooth_noise(n, cells, rng):
    """1-D tileable value noise: n samples, `cells` random knots, cosine-interpolated."""
    knots = rng.random(cells)
    t = np.arange(n) * cells / n
    i = np.floor(t).astype(int)
    f = t - i
    f = (1 - np.cos(f * np.pi)) / 2
    return knots[i % cells] * (1 - f) + knots[(i + 1) % cells] * f


def textures(size=512, seed=7):
    rng = np.random.default_rng(seed)
    # streaks run along u (x): each row gets its own brightness, varying slowly along the row
    rows = sum(_smooth_noise(size, c, rng) * w for c, w in ((size // 2, 0.5), (size // 8, 0.3), (size // 32, 0.2)))
    along = np.stack([_smooth_noise(size, 6, rng) for _ in range(8)])
    streak = rows[:, None] * (0.85 + 0.15 * along[np.arange(size) % 8][:, :])
    fine = rng.random((size, size)) * 0.5 + 0.5
    fine = (fine + np.roll(fine, 1, 1) + np.roll(fine, 2, 1) + np.roll(fine, 3, 1)) / 4  # smear along u
    v = 0.86 + 0.045 * (streak - streak.mean()) / (streak.std() + 1e-9) * 0.5 + 0.025 * (fine - 0.75)
    albedo = np.clip(v, 0, 1)
    rough = np.clip(0.34 + 0.10 * (albedo.mean() - albedo) / (albedo.std() + 1e-9) * 0.5, 0.2, 0.55)
    a8 = (albedo * 255).astype(np.uint8)
    alb = Image.fromarray(np.stack([a8, a8, (np.clip(albedo * 1.01, 0, 1) * 255).astype(np.uint8)], -1), "RGB")
    mr = np.zeros((size, size, 3), np.uint8)
    mr[..., 1] = (rough * 255).astype(np.uint8)   # G: roughness
    mr[..., 2] = 255                               # B: metallic
    mrim = Image.fromarray(mr, "RGB")
    out = []
    for im in (alb, mrim):
        b = io.BytesIO(); im.save(b, "PNG", optimize=True); out.append(b.getvalue())
    return out


def box_uv(P, N, tile=0.6):
    """Box-projected UVs (one tile per `tile` metres); streaks (u) run horizontally on the sides."""
    a = np.abs(N)
    uv = np.empty((len(P), 2))
    top = (a[:, 1] >= a[:, 0]) & (a[:, 1] >= a[:, 2])
    side_x = ~top & (a[:, 0] >= a[:, 2])
    side_z = ~top & ~side_x
    uv[top] = P[top][:, [0, 2]]
    uv[side_x] = np.stack([P[side_x][:, 2], -P[side_x][:, 1]], 1)
    uv[side_z] = np.stack([P[side_z][:, 0], -P[side_z][:, 1]], 1)
    return uv / tile
