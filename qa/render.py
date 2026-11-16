from PIL import Image, ImageDraw, ImageFont
import textwrap
K = 2
FONTS = {}
def font(name):
    size = 10
    if "Large" in name or "Title" in name: size = 15
    elif name in ("GameFontNormal", "GameFontHighlight", "SterlingFont", "QuestFont"): size = 12
    key = size
    if key not in FONTS: FONTS[key] = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf", int(size * K * 0.92))
    return FONTS[key], size
def col(s, default=(40, 40, 40, 255)):
    if not s: return None
    p = [float(x) for x in s.split(",")]
    while len(p) < 4: p.append(1.0)
    return tuple(int(max(0, min(1, v)) * 255) for v in p)
def render(L, winname, path, pad=28, top_extra=30, bottom_extra=44):
    dump, w, h = L.eval("function(n) return DUMP(_G[n]) end")(winname)
    W, H = int((w + pad * 2) * K), int((h + pad + top_extra + bottom_extra) * K)
    img = Image.new("RGBA", (W, H), (58, 60, 66, 255))
    ox, oy = pad * K, top_extra * K
    for line in str(dump).split("\n"):
        f = line.split("\t")
        if len(f) < 11: continue
        kind = f[0]; x, y, ww, hh = [float(v) * K for v in f[1:5]]
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
        box = [ox + x, oy + y, ox + x + ww, oy + y + hh]
        if kind == "Texture":
            c = col(f[5]);
            if c and ww > 0 and hh > 0: d.rectangle(box, fill=c)
        elif kind == "FontString":
            c = col(f[5]) or (230, 222, 202, 255)
            fnt, size = font(f[7]); text = f[6]
            lines = []
            for para in text.split("\n"):
                if f[9] == "wrap" and ww > 20:
                    cur = ""
                    for word in para.split(" "):
                        t = (cur + " " + word).strip()
                        if d.textlength(t, font=fnt) <= ww or not cur: cur = t
                        else: lines.append(cur); cur = word
                    lines.append(cur)
                else: lines.append(para)
            lh = (size + 2) * K
            ty = oy + y + max(0, (hh - lh * len(lines)) / 2) if len(lines) == 1 else oy + y
            for ln in lines:
                tw = d.textlength(ln, font=fnt)
                tx = ox + x
                if f[8] == "CENTER": tx = ox + x + (ww - tw) / 2
                elif f[8] == "RIGHT": tx = ox + x + ww - tw
                d.text((tx, ty), ln, font=fnt, fill=c); ty += lh
        else:
            bg, edge, tpl, text, state = col(f[5]), col(f[8]), f[7], f[6], f[9]
            if tpl == "UIPanelButtonTemplate":
                d.rounded_rectangle(box, radius=4, fill=(96, 24, 20, 255) if state != "off" else (60, 54, 52, 255), outline=(150, 120, 60, 255))
                fnt, size = font("GameFontNormalSmall" if hh < 40 else "GameFontNormal")
                tw = d.textlength(text, font=fnt); d.text((ox + x + (ww - tw) / 2, oy + y + (hh - size * K) / 2 - 1), text, font=fnt, fill=(255, 210, 0, 255) if state != "off" else (140, 140, 140, 255))
            elif tpl and "UICheckButton" in tpl:
                b2 = [box[0] + 4 * K, box[1] + 4 * K, box[2] - 4 * K, box[3] - 4 * K]
                d.rectangle(b2, fill=(20, 18, 14, 255), outline=(150, 120, 60, 255))
                if state == "checked": d.line([b2[0] + 3, (b2[1] + b2[3]) / 2, (b2[0] + b2[2]) / 2, b2[3] - 3, b2[2] - 2, b2[1] + 2], fill=(255, 210, 0, 255), width=3)
            elif tpl == "UIPanelCloseButton":
                d.rounded_rectangle([box[0] + 6, box[1] + 6, box[2] - 6, box[3] - 6], radius=4, fill=(120, 26, 20, 255), outline=(150, 120, 60, 255))
            elif tpl == "InputBoxTemplate":
                d.rectangle([box[0] - 5 * K, box[1], box[2], box[3]], fill=(10, 10, 12, 255), outline=(120, 110, 90, 255))
            elif tpl == "OptionsSliderTemplate":
                d.rectangle([box[0], (box[1] + box[3]) / 2 - 3, box[2], (box[1] + box[3]) / 2 + 3], fill=(30, 28, 24, 255), outline=(120, 110, 90, 255))
            elif tpl == "UIPanelScrollFrameTemplate":
                d.rectangle([box[2] + 4 * K, box[1], box[2] + 20 * K, box[3]], fill=(24, 22, 20, 255), outline=(90, 80, 60, 255))
            elif bg or edge:
                if ww > 0 and hh > 0: d.rectangle(box, fill=bg or None, outline=edge or None)
        if f[10]:
            cx, cy, cw, ch = [float(v) * K for v in f[10].split(",")]
            mask = Image.new("L", (W, H), 0); ImageDraw.Draw(mask).rectangle([ox + cx, oy + cy, ox + cx + cw, oy + cy + ch], fill=255)
            layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", (W, H), 0), mask))
        img = Image.alpha_composite(img, layer)
    img.convert("RGB").save(path)
    return path
