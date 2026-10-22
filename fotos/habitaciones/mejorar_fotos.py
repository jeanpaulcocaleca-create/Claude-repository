"""Realce fotográfico suave para fotos de habitaciones (estilo real-estate / hotel).

Pasos (todo en sRGB float 0..1):
  1. Balance de blancos por "parche blanco" (paredes/sábanas) mezclado con el original.
  2. Sombras / luces con máscara de luminancia desenfocada (levanta techo y rincones,
     recupera un poco las zonas claras).
  3. Pequeña subida de exposición en medios tonos + curva S suave.
  4. Claridad (contraste local de radio grande, cantidad baja, sin halos).
  5. Vibrance (satura más lo poco saturado, protege lo ya saturado).
  6. Enfoque suave (unsharp mask) al final.
Uso: python3 -I mejorar_fotos.py <entrada...> --out <carpeta>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont


# ---------- utilidades ----------
def box_blur_1d(a, r, axis):
    """Box blur de radio r (entero) a lo largo de un eje, con bordes replicados."""
    if r <= 0:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r, r)
    ap = np.pad(a, pad, mode="edge")
    cs = np.cumsum(ap, axis=axis, dtype=np.float64)
    n = a.shape[axis]
    w = 2 * r + 1
    # sum over window [i, i+w) in padded coords == cs[i+w-1] - cs[i-1]
    cs = np.concatenate([np.zeros_like(np.take(cs, [0], axis=axis)), cs], axis=axis)
    hi = np.take(cs, np.arange(w, w + n), axis=axis)
    lo = np.take(cs, np.arange(0, n), axis=axis)
    return (hi - lo) / w


def gaussian_blur(a, sigma):
    """Aproximación gaussiana con 3 box blurs (2D array)."""
    r = max(1, int(round(sigma * 0.87)))  # 3 cajas de radio r ~ gaussiana sigma
    out = a.astype(np.float64)
    for _ in range(3):
        out = box_blur_1d(out, r, 0)
        out = box_blur_1d(out, r, 1)
    return out


def luminance(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


# ---------- pasos ----------
def white_balance(rgb, strength=0.75, min_gain=0.88, max_gain=1.18):
    L = luminance(rgb)
    sat = rgb.max(-1) - rgb.min(-1)
    # píxeles claros, no quemados y casi neutros: paredes, sábanas, techo
    thr = np.percentile(L, 90)
    mask = (L >= thr) & (L < 0.97) & (sat < 0.12)
    if mask.sum() < 500:
        mask = (L >= np.percentile(L, 85)) & (L < 0.98)
    ref = rgb[mask].mean(0)
    gains = ref.mean() / ref
    gains = np.clip(gains, min_gain, max_gain)
    # Enfriar (quitar dominante amarilla) se permite libremente; calentar casi nada,
    # para que paredes y sábanas no se vuelvan color crema.
    gains[0] = min(gains[0], 1.02)   # rojo no sube más de 2 %
    gains[2] = max(gains[2], 0.98)   # azul no baja más de 2 %
    gains = 1.0 + strength * (gains - 1.0)
    return np.clip(rgb * gains, 0, 1), gains


def shadows_highlights(rgb, shadows=0.35, highlights=0.18, sigma=45):
    L = luminance(rgb)
    Lb = gaussian_blur(L, sigma)
    smask = np.clip(1.0 - Lb / 0.60, 0, 1) ** 1.4
    hmask = np.clip((Lb - 0.62) / 0.38, 0, 1) ** 1.4
    gamma = (1.0 + highlights * hmask) / (1.0 + shadows * smask)
    out = np.power(np.clip(rgb, 1e-6, 1), gamma[..., None])
    return out


def midtone_lift(rgb, amount=0.10):
    return np.clip(rgb + amount * rgb * (1 - rgb), 0, 1)


def s_curve(rgb, k=0.22):
    smooth = rgb * rgb * (3 - 2 * rgb)
    return (1 - k) * rgb + k * smooth


def clarity(rgb, amount=0.18, sigma=22):
    L = luminance(rgb)
    Lb = gaussian_blur(L, sigma)
    Ln = np.clip(L + amount * (L - Lb), 0, 1)
    ratio = Ln / np.maximum(L, 1e-4)
    ratio = np.clip(ratio, 0.6, 1.5)
    return np.clip(rgb * ratio[..., None], 0, 1)


def vibrance(rgb, v=0.20):
    mean = rgb.mean(-1, keepdims=True)
    sat = (rgb.max(-1) - rgb.min(-1))[..., None]
    return np.clip(mean + (rgb - mean) * (1 + v * (1 - sat)), 0, 1)


def soft_clip_highlights(rgb, knee=0.90):
    # comprime suavemente por encima de knee para no quemar más las ventanas
    x = rgb
    over = x > knee
    y = x.copy()
    t = (x[over] - knee) / (1 - knee)
    y[over] = knee + (1 - knee) * (1 - (1 - t) ** 2) * 0.5 + (1 - knee) * t * 0.5
    return y


def enhance(im, params=None):
    p = dict(wb=0.75, shadows=0.35, highlights=0.18, lift=0.10, s=0.22,
             clarity=0.18, vib=0.20, sharpen=(1.0, 70, 2))
    if params:
        p.update(params)
    rgb = np.asarray(im.convert("RGB")).astype(np.float64) / 255.0
    rgb, gains = white_balance(rgb, strength=p["wb"])
    if "wb_extra" in p:  # corrección manual adicional (R, G, B)
        extra = np.array(p["wb_extra"], dtype=np.float64)
        rgb = np.clip(rgb * extra, 0, 1)
        gains = gains * extra
    rgb = shadows_highlights(rgb, p["shadows"], p["highlights"])
    rgb = midtone_lift(rgb, p["lift"])
    rgb = s_curve(rgb, p["s"])
    rgb = clarity(rgb, p["clarity"])
    rgb = vibrance(rgb, p["vib"])
    rgb = soft_clip_highlights(rgb)
    out = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))
    r, pct, thr = p["sharpen"]
    out = out.filter(ImageFilter.UnsharpMask(radius=r, percent=pct, threshold=thr))
    return out, gains


def side_by_side(a, b, label_a="ANTES", label_b="DESPUÉS"):
    w, h = a.size
    canvas = Image.new("RGB", (w * 2 + 12, h + 44), (24, 24, 24))
    canvas.paste(a, (0, 44))
    canvas.paste(b, (w + 12, 44))
    d = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
    except Exception:
        font = ImageFont.load_default()
    d.text((16, 9), label_a, fill=(235, 235, 235), font=font)
    d.text((w + 28, 9), label_b, fill=(235, 235, 235), font=font)
    return canvas


def main(argv):
    if "--out" not in argv:
        print(__doc__)
        return 1
    i = argv.index("--out")
    out_dir = argv[i + 1]
    inputs = argv[:i] + argv[i + 2:]
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(os.path.join(out_dir, "comparacion"), exist_ok=True)
    for path in inputs:
        im = Image.open(path)
        name = os.path.splitext(os.path.basename(path))[0]
        per_image = PER_IMAGE.get(name, {})
        out, gains = enhance(im, per_image)
        dst = os.path.join(out_dir, f"habitacion-{name}-mejorada.jpg")
        out.save(dst, "JPEG", quality=94, subsampling=0, optimize=True)
        cmp_path = os.path.join(out_dir, "comparacion", f"{name}-antes-despues.jpg")
        side_by_side(im.convert("RGB"), out).save(cmp_path, "JPEG", quality=88)
        print(f"{name}: WB gains R/G/B = {np.round(gains, 3)} -> {dst}")
    return 0


# Ajustes por foto (nombre de archivo sin extensión)
PER_IMAGE = {
    # foto 1: dominante cálida (pared de madera + luz), techo oscuro
    "1": dict(wb=0.0, wb_extra=(0.975, 1.0, 1.035), shadows=0.40, highlights=0.15, vib=0.14),
    # fotos 2/3: contraluz de ventana, pared y techo grises
    "2": dict(wb=0.7, shadows=0.40, highlights=0.25),
    "3": dict(wb=0.7, shadows=0.40, highlights=0.25),
    # foto 4: ya bastante neutra, solo abrir un poco y dar vida
    "4": dict(wb=0.6, shadows=0.32, highlights=0.20),
    # fotos 5/6: techo de madera oscuro, luz plana, pared algo grisácea
    "5": dict(wb=0.7, shadows=0.42, highlights=0.22, clarity=0.20),
    "6": dict(wb=0.7, shadows=0.42, highlights=0.22, clarity=0.20),
    # foto 7: ya clara, pared con leve tono amarillo-verdoso
    "7": dict(wb=0.0, wb_extra=(0.985, 0.995, 1.035), shadows=0.30, highlights=0.22, lift=0.06, vib=0.14),
    # foto 8: archivo idéntico a la 1
    "8": dict(wb=0.0, wb_extra=(0.975, 1.0, 1.035), shadows=0.40, highlights=0.15, vib=0.14),
}

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
