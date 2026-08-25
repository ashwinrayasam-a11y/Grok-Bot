"""Front-view render of Vesper's stylized face geometry.

Mirrors the math in ios/Vesper/Vesper/Avatar/AvatarGeometry.swift (enum
Stylized + the eye/brow/lip builders) so the face can be proportion-checked
and tuned without an Xcode rebuild. Run:

    python3 tools/face_preview.py out.png

Keep the constants in sync with the Swift by hand — this is a tuning aid,
not a source of truth.
"""

from __future__ import annotations

import math
import sys

from PIL import Image, ImageDraw

# --- Constants mirrored from Swift (Stylized / AvatarGeometry) ---

HEAD_KEYS = [
    (0.096, 0.014, 0.014, 0.014, 2.0),
    (0.082, 0.046, 0.050, 0.055, 2.0),
    (0.058, 0.061, 0.062, 0.070, 2.1),
    (0.030, 0.068, 0.067, 0.076, 2.2),
    (0.000, 0.072, 0.071, 0.077, 2.3),
    (-0.028, 0.0725, 0.071, 0.071, 2.3),
    (-0.045, 0.065, 0.069, 0.062, 2.25),
    (-0.058, 0.053, 0.067, 0.054, 2.2),
    (-0.070, 0.039, 0.063, 0.044, 2.15),
    (-0.080, 0.025, 0.058, 0.034, 2.05),
    (-0.088, 0.013, 0.052, 0.024, 2.0),
    (-0.093, 0.005, 0.044, 0.016, 2.0),
]

EYE_Y = -0.008
EYE_SPACING = 0.036
EYE_WIDTH = 0.036
EYE_TILT = 0.12
ALMOND_UP = 0.0112
ALMOND_UP_POW = 0.88
ALMOND_LO = 0.0078
IRIS_R = 0.0085
LASH_TH = 0.0042
WING_LEN = 0.16      # t extension past 1.0
WING_RISE = 0.055
BROW = dict(x0=0.014, x1=0.056, y0=0.0125, rise=0.0095, fall=0.0095, peak=0.66,
            th=0.0042, th_taper=0.68)
MOUTH_Y = -0.050
MOUTH_HALF_W = 0.018
LIP_UP = 0.0046
LIP_DIP = 0.0016
LIP_LO = 0.0084
LIPLINE_DROP = 0.0012
NOSE_TOP = -0.012
NOSE_LEN = 0.016
NOSE_HALF_W = 0.0030
HAIRLINE_Y = 0.040  # arc handled below: center 0.048 dipping to 0.030 at temples
CURTAIN_INNER0 = 0.048

INK = (20, 15, 12)
SKIN = (240, 217, 199)
SKIN_SHADE = (219, 192, 172)
HAIR = (26, 19, 14)
MAKEUP = (19, 14, 11)
SCLERA = (242, 237, 229)
IRIS = (98, 108, 88)
PUPIL = (14, 13, 12)
LIP = (97, 31, 48)
SHADOW = (208, 178, 158)


def smoothstep(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def profile(y: float):
    yy = min(HEAD_KEYS[0][0], max(HEAD_KEYS[-1][0], y))
    for i in range(len(HEAD_KEYS) - 1):
        a, b = HEAD_KEYS[i], HEAD_KEYS[i + 1]
        if b[0] <= yy <= a[0]:
            t = smoothstep((a[0] - yy) / max(a[0] - b[0], 1e-6))
            return tuple(a[k] + (b[k] - a[k]) * t for k in range(1, 5))
    return HEAD_KEYS[-1][1:]


def almond_upper(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return ALMOND_UP * math.sin(math.pi * t ** ALMOND_UP_POW) ** 0.9


def almond_lower(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return -ALMOND_LO * math.sin(math.pi * t)


# --- Rendering ---

SS = 4                      # supersample
H_PX = 900 * SS
SCALE = H_PX / 0.26         # meters -> px, head 0.188 tall in 0.26 window
CX, CY = 640 * SS // 2, int(H_PX * 0.47)


def to_px(x: float, y: float):
    return (CX + x * SCALE, CY - y * SCALE)


def poly(draw, pts, fill):
    draw.polygon([to_px(x, y) for x, y in pts], fill=fill)


def eye_space(t: float, y_off: float, side: int):
    """Almond param -> head space (applies tilt about the eye center)."""
    lx = side * (t - 0.5) * EYE_WIDTH
    ly = y_off
    a = side * EYE_TILT
    x = lx * math.cos(a) - ly * math.sin(a) + side * EYE_SPACING
    y = lx * math.sin(a) + ly * math.cos(a) + EYE_Y
    return (x, y)


def render(path: str):
    img = Image.new("RGB", (640 * SS, 900 * SS), INK)
    d = ImageDraw.Draw(img)

    ys = [HEAD_KEYS[0][0] - i * (HEAD_KEYS[0][0] - HEAD_KEYS[-1][0]) / 80 for i in range(81)]

    # Back hair sheet (framing silhouette behind the head)
    hair_back = [(-profile(y)[0] - 0.028 - 0.012 * (HEAD_KEYS[0][0] - y), y) for y in ys]
    hair_back += [(profile(y)[0] + 0.028 + 0.012 * (HEAD_KEYS[0][0] - y), y) for y in reversed(ys)]
    hair_back += [(0.16, -0.30), (-0.16, -0.30)]
    poly(d, hair_back[:162], HAIR)
    d.polygon(
        [to_px(-0.155, -0.05), to_px(0.155, -0.05), to_px(0.17, -0.42), to_px(-0.17, -0.42)],
        fill=HAIR,
    )

    # Head silhouette
    outline = [(-profile(y)[0], y) for y in ys] + [(profile(y)[0], y) for y in reversed(ys)]
    poly(d, outline, SKIN)

    # Neck hint
    d.polygon([to_px(-0.024, -0.075), to_px(0.024, -0.075), to_px(0.027, -0.16), to_px(-0.027, -0.16)], fill=SKIN_SHADE)

    # Scalp hair down to an ARCED hairline: high at center, dipping at temples
    wref = profile(0.03)[0]
    arc = []
    for i in range(61):
        u = i / 60 * 2 - 1                     # -1..1 across the forehead
        x = u * wref
        y = 0.048 - 0.018 * (abs(u) ** 1.6)    # center 0.048 -> temples 0.030
        arc.append((x, y))
    cap = [( -profile(y)[0] * 1.03, y) for y in ys if y >= 0.028]
    cap += arc
    cap += [(profile(y)[0] * 1.03, y) for y in reversed(ys) if y >= 0.028]
    poly(d, cap, HAIR)

    # Front curtains (inner edges past the temples)
    for side in (-1, 1):
        pts = []
        for i in range(25):
            t = i / 24
            inner = CURTAIN_INNER0 + 0.026 * t ** 0.9
            pts.append((side * inner, 0.062 - 0.52 * t))
        for i in range(25):
            t = 1 - i / 24
            inner = CURTAIN_INNER0 + 0.026 * t ** 0.9 + 0.038 + 0.024 * t
            pts.append((side * inner, 0.062 - 0.52 * t))
        poly(d, pts, HAIR)

    # Nose: subtle shade + tip line
    d.polygon(
        [to_px(-0.0016, NOSE_TOP), to_px(0.0016, NOSE_TOP),
         to_px(NOSE_HALF_W, NOSE_TOP - NOSE_LEN), to_px(-NOSE_HALF_W, NOSE_TOP - NOSE_LEN)],
        fill=SHADOW,
    )
    d.line([to_px(-NOSE_HALF_W * 0.9, NOSE_TOP - NOSE_LEN), to_px(NOSE_HALF_W * 0.9, NOSE_TOP - NOSE_LEN)],
           fill=SKIN_SHADE, width=2 * SS)

    # Eyes
    for side in (-1, 1):
        n = 24
        # sclera
        pts = [eye_space(i / n, almond_lower(i / n), side) for i in range(n + 1)]
        pts += [eye_space(1 - i / n, almond_upper(1 - i / n), side) for i in range(n + 1)]
        poly(d, pts, SCLERA)
        # iris (clipped look approximated by drawing then lash overlap)
        cx, cy = eye_space(0.5, 0.0, side)
        d.ellipse([to_px(cx - IRIS_R, cy + IRIS_R), to_px(cx + IRIS_R, cy - IRIS_R)], fill=IRIS)
        d.ellipse([to_px(cx - IRIS_R * 0.42, cy + IRIS_R * 0.42), to_px(cx + IRIS_R * 0.42, cy - IRIS_R * 0.42)], fill=PUPIL)
        gx, gy = cx - side * 0.0032, cy + 0.0034
        d.ellipse([to_px(gx - 0.0021, gy + 0.0021), to_px(gx + 0.0021, gy - 0.0021)], fill=(250, 246, 240))
        # upper lash band + wing
        n2 = 30
        top = []
        bot = []
        for i in range(n2 + 1):
            t = i / n2 * (1 + WING_LEN)
            base = min(t, 1.0)
            wing = max(0.0, t - 1.0)
            th = LASH_TH * (0.35 + 0.65 * math.sin(math.pi * min(base, 1.0))) + wing * 0.01
            y0 = almond_upper(base) + wing * WING_RISE
            lx = side * (t - 0.5) * EYE_WIDTH
            a = side * EYE_TILT
            for arr, yy in ((bot, y0), (top, y0 + th)):
                x = lx * math.cos(a) - yy * math.sin(a) + side * EYE_SPACING
                y = lx * math.sin(a) + yy * math.cos(a) + EYE_Y
                arr.append((x, y))
        poly(d, bot + list(reversed(top)), MAKEUP)
        # lower liner
        lo = [eye_space(0.18 + (1.04 - 0.18) * i / n, almond_lower(0.18 + (1.04 - 0.18) * i / n) - 0.0011, side) for i in range(n + 1)]
        hi = [eye_space(0.18 + (1.04 - 0.18) * (1 - i / n), almond_lower(0.18 + (1.04 - 0.18) * (1 - i / n)), side) for i in range(n + 1)]
        poly(d, lo + hi, MAKEUP)
        # lid droop hint (rest ~15%)
        droop = []
        for i in range(n + 1):
            t = i / n
            droop.append(eye_space(t, almond_upper(t), side))
        for i in range(n + 1):
            t = 1 - i / n
            droop.append(eye_space(t, almond_upper(t) * 0.7, side))
        poly(d, droop, (176, 138, 128))

    # Brows
    for side in (-1, 1):
        n = 20
        lo, hi = [], []
        for i in range(n + 1):
            t = i / n
            rise = min(1.0, t / BROW["peak"])
            fall = max(0.0, (t - BROW["peak"]) / (1 - BROW["peak"]))
            y = BROW["y0"] + BROW["rise"] * rise - BROW["fall"] * fall
            x = side * (BROW["x0"] + BROW["x1"] * t)
            th = BROW["th"] * (1 - BROW["th_taper"] * t) + 0.0008
            lo.append((x, y))
            hi.append((x, y + th))
        poly(d, lo + list(reversed(hi)), MAKEUP)

    # Lips
    n = 20
    upper_out, lower_out, lipline = [], [], []
    for i in range(-n, n + 1):
        t = abs(i) / n
        sgn = -1 if i < 0 else 1
        x = sgn * MOUTH_HALF_W * t
        line_y = MOUTH_Y - 0.0006 - LIPLINE_DROP * t * t
        dip = LIP_DIP * math.exp(-((t / 0.15) ** 2))
        up = line_y + LIP_UP * (1 - t ** 1.6) - dip + 0.0006
        lo = line_y - LIP_LO * (1 - t ** 1.5)
        lipline.append((x, line_y))
        upper_out.append((x, up))
        lower_out.append((x, lo))
    poly(d, upper_out + list(reversed(lipline)), LIP)
    poly(d, lipline + list(reversed(lower_out)), LIP)
    d.line([to_px(*p) for p in lipline], fill=(60, 16, 28), width=2 * SS)

    img = img.resize((640, 900), Image.LANCZOS)
    img.save(path)
    print("saved", path)

    # numeric proportion report
    top, chin = HEAD_KEYS[0][0], HEAD_KEYS[-1][0]
    hh = top - chin
    print(f"head h={hh:.3f} w={2*profile(EYE_Y)[0]:.3f}  w/h={2*profile(EYE_Y)[0]/hh:.2f}")
    print(f"eye line from top: {(top-EYE_Y)/hh:.2f}  (0.50-0.58 good)")
    print(f"eye gap/eye width: {(2*(EYE_SPACING-EYE_WIDTH/2))/EYE_WIDTH:.2f}  (~1.0 good)")
    print(f"temple margin/eye width: {(profile(EYE_Y)[0]-(EYE_SPACING+EYE_WIDTH/2))/EYE_WIDTH:.2f} (~0.4-0.6)")
    print(f"mouth width/face width at mouth: {2*MOUTH_HALF_W/(2*profile(MOUTH_Y)[0]):.2f} (~0.30-0.38)")
    print(f"nose tip->mouth: {abs(NOSE_TOP-NOSE_LEN-MOUTH_Y):.3f}  mouth->chin: {abs(MOUTH_Y-chin):.3f}")


if __name__ == "__main__":
    render(sys.argv[1] if len(sys.argv) > 1 else "/tmp/vesper_face_preview.png")
