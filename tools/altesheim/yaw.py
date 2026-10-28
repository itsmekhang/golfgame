import numpy as np
def _cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def min_area_yaw(xz):
    """Yaw (deg, -45..45) that best axis-aligns the 2D point set (min-area bounding box over the convex hull)."""
    pts = np.unique(np.round(xz, 4), axis=0)
    # convex hull (monotone chain)
    pts = pts[np.lexsort((pts[:, 1], pts[:, 0]))]
    def half(ps):
        h = []
        for p in ps:
            while len(h) >= 2 and _cross(h[-1] - h[-2], p - h[-2]) <= 0: h.pop()
            h.append(p)
        return h
    hull = np.array(half(pts)[:-1] + half(pts[::-1])[:-1])
    best = (np.inf, 0.0)
    for deg in np.arange(-45, 45.001, 0.05):
        a = np.radians(deg); c, s = np.cos(a), np.sin(a)
        q = hull @ np.array([[c, -s], [s, c]]).T
        ext = q.max(0) - q.min(0)
        area = ext[0] * ext[1]
        if area < best[0] - 1e-9: best = (area, deg)
    return best[1]
