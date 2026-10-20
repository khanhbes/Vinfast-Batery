"""Cut the owner's metal Pinova logo off its dark backdrop (QA 133 splash).

Composite model C = a*F + (1-a)*B. B is the backdrop inpainted under the mark;
solid metal gets a = 1, the soft glow the smallest alpha that explains it.
Two layers come out: the metal (with the white knob) and the emerald track +
glow, so the splash can run the charge along the real artwork.
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

src = sys.argv[1]
out_dir = sys.argv[2]
img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
lum = img.mean(axis=2)
g_dom = img[..., 1] - np.maximum(img[..., 0], img[..., 2])

# Rough backdrop: a heavy blur of the image with the mark painted out.
rough = (lum > 40) | (g_dom > 10)
mask = cv2.dilate(rough.astype(np.uint8) * 255, np.ones((41, 41), np.uint8))
bg = cv2.inpaint(img.astype(np.uint8), mask, 30, cv2.INPAINT_TELEA).astype(np.float32)
bg = cv2.GaussianBlur(bg, (0, 0), 25)

diff = np.clip(img - bg, 0, None)
alpha = np.max(diff / np.maximum(255 - bg, 1), axis=2)
# Solid metal: bright and grey, holes filled.
solid = ((lum - bg.mean(axis=2)) > 55).astype(np.uint8)
solid = cv2.morphologyEx(solid, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
alpha = np.where(solid > 0, 1.0, alpha)
alpha = np.clip(alpha, 0, 1)
a3 = alpha[..., None]
fg = np.where(a3 > 1e-3, (img - (1 - a3) * bg) / np.maximum(a3, 1e-3), 0)
fg = np.clip(fg, 0, 255)

# Split by hue: emerald pixels (track + glow) vs the metal.
w = np.clip((g_dom - 12) / 40.0, 0, 1)
w = cv2.GaussianBlur(w, (0, 0), 1.2)


def save(name, a):
    rgba = np.dstack([fg, np.clip(a, 0, 1) * 255]).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(out_dir, name))


save("pinova_logo_full.png", alpha)
save("pinova_logo_metal.png", alpha * (1 - w))
save("pinova_logo_charge.png", alpha * w)

# Preview: composited on the splash ground, full and metal-only.
ground = np.zeros_like(img)
ground[...] = (5, 5, 6)
for name, a in (("prev_full.png", alpha), ("prev_metal.png", alpha * (1 - w))):
    a3 = a[..., None]
    comp = fg * a3 + ground * (1 - a3)
    Image.fromarray(comp.astype(np.uint8)).resize((400, 400)).save(os.path.join(out_dir, name))
print("done", float(alpha.mean()))
