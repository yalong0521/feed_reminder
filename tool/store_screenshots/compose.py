"""Compose store posters from real app captures using one measured template.

Requires Pillow and locally installed Microsoft YaHei (not redistributed).
Raw Flutter frames remain unchanged; a single mask controls every app viewport.
The widget panel explicitly combines three current ArkUI Previewer captures.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BG = '#faf5ed'
INK = '#ac5638'
BODY = '#6f6055'


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text(draw, xy, value, font, color=BODY):
    draw.text(xy, value, font=font, fill=color, anchor='lt')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'build/store-assets-1.1.0-5/raw')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/store-assets-1.1.0-5/posters')
    parser.add_argument('--fonts', type=Path, default=Path('C:/Windows/Fonts'))
    args = parser.parse_args()
    spec = json.loads(Path(__file__).with_name('listing.json').read_text(encoding='utf-8'))
    geometry = spec['poster']
    width, height = geometry['width'], geometry['height']
    ax, ay = geometry['appX'], geometry['appY']
    aw, ah, radius = geometry['appWidth'], geometry['appHeight'], geometry['appRadius']
    args.output.mkdir(parents=True, exist_ok=True)

    def font(size, bold=False):
        return ImageFont.truetype(str(args.fonts / ('msyhbd.ttc' if bold else 'msyh.ttc')), size)

    mask = Image.new('L', (aw, ah))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, aw - 1, ah - 1), radius=radius, fill=255)
    mask_hash = hashlib.sha256(mask.tobytes()).hexdigest()
    entries = []
    for index, shot in enumerate(spec['screenshots'], start=1):
        native = shot.get('kind') == 'native-widget-composition'
        sources = []
        if native:
            panel = Image.new('RGB', (aw, ah), '#f5eee4')
            pd = ImageDraw.Draw(panel)
            text(pd, (48, 52), '鸿蒙原生卡片', font(38, True), INK)
            text(pd, (48, 113), '按桌面空间，自由选择尺寸', font(26))
            widgets = [
                ('QaNormalWide-light.jpg', (48, 246), (768, 384), '4×2 · 喂养概览', (48, 194)),
                ('QaNormalSquare-light.jpg', (48, 762), (365, 384), '2×2 · 最近一餐', (48, 710)),
                ('QaNormalCompact-light.jpg', (451, 762), (365, 131), '2×1 · 下次喂奶', (451, 710)),
            ]
            for name, pos, size, label, label_pos in widgets:
                source = args.source / 'widgets' / name
                sources.append({'file': str(source), 'sha256': sha256(source)})
                with Image.open(source) as raw:
                    # Preserve the entire rendered card at its original aspect ratio.
                    if abs(raw.width / raw.height - size[0] / size[1]) > .01:
                        raise ValueError(f'Card aspect ratio changed: {source}')
                    rendered = raw.convert('RGB').resize(size, Image.Resampling.LANCZOS)
                card_mask = Image.new('L', size)
                ImageDraw.Draw(card_mask).rounded_rectangle((0, 0, size[0]-1, size[1]-1), radius=47, fill=255)
                panel.paste(rendered, pos, card_mask)
                text(pd, label_pos, label, font(28, True))
            text(pd, (458, 949), '下次喂奶时间', font(27, True), INK)
            text(pd, (458, 997), '抬眼就能看到', font(27))
            pd.line((48, 1250, aw - 48, 1250), fill='#dfd2c1', width=2)
            text(pd, (48, 1301), '点击卡片，进入应用继续记录', font(31, True), INK)
            text(pd, (48, 1364), '卡片按系统允许的时机刷新', font(25))
        else:
            source = args.source / shot['file']
            sources.append({'file': str(source), 'sha256': sha256(source)})
            with Image.open(source) as raw:
                if raw.size != (aw, ah):
                    raise ValueError(f'{source}: expected {(aw, ah)}, got {raw.size}')
                panel = raw.convert('RGB')

        poster = Image.new('RGB', (width, height), BG)
        draw = ImageDraw.Draw(poster)
        text(draw, (108, 48), '奶点记', font(32, True), INK)
        badge = f'{index:02d} / {len(spec["screenshots"]):02d}'
        draw.text((972, 48), badge, font=font(23), fill='#9a8272', anchor='rt')
        headline = font(78, True)
        if draw.textlength(shot['title'], font=headline) > 900:
            raise ValueError(f'Headline does not fit the shared template: {shot["title"]}')
        text(draw, (104, 119), shot['title'], headline, INK)
        if draw.textlength(shot['subtitle'], font=font(30)) > aw:
            raise ValueError(f'Subtitle does not fit: {shot["subtitle"]}')
        text(draw, (108, 229), shot['subtitle'], font(30))

        shadow = Image.new('RGBA', (width, height))
        ImageDraw.Draw(shadow).rounded_rectangle((ax-4, ay+9, ax+aw+4, ay+ah+16), radius=radius+8, fill=(115, 67, 36, 35))
        poster = Image.alpha_composite(poster.convert('RGBA'), shadow.filter(ImageFilter.GaussianBlur(20)))
        draw = ImageDraw.Draw(poster)
        draw.rounded_rectangle((ax-8, ay-8, ax+aw+7, ay+ah+7), radius=radius+8, fill='#fffdf8')
        poster.paste(panel, (ax, ay), mask)
        destination = args.output / shot['file']
        poster.convert('RGB').save(destination, optimize=True)
        if destination.stat().st_size >= 5 * 1024 * 1024:
            raise ValueError(f'AppGallery 5 MiB limit exceeded: {destination}')
        entries.append({'file': shot['file'], 'title': shot['title'], 'size': [width, height],
                        'appViewport': [ax, ay, aw, ah], 'appRadius': radius,
                        'maskSha256': mask_hash, 'sha256': sha256(destination),
                        'bytes': destination.stat().st_size, 'sources': sources,
                        'captureType': 'ArkUI preview composition with isolated demo data' if native else 'real Flutter Web UI with isolated demo data'})

    manifest = {'version': f'{spec["versionName"]}+{spec["versionCode"]}', 'layout': geometry,
                'windowsChromeIncluded': False, 'allViewportsIdentical': True, 'files': entries}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    thumbs = []
    for entry in entries:
        with Image.open(args.output / entry['file']) as image:
            thumbs.append(image.resize((216, 384), Image.Resampling.LANCZOS))
    contact = Image.new('RGB', (216 * 5, 384 * 2), '#ffffff')
    for i, thumb in enumerate(thumbs):
        contact.paste(thumb, ((i % 5) * 216, (i // 5) * 384))
    contact.save(args.output / 'contact-sheet.jpg', quality=95)
    cards = '\n'.join(f'<figure><img src="{html.escape(e["file"])}"><figcaption>{i+1:02d} · {html.escape(e["title"])}</figcaption></figure>' for i,e in enumerate(entries))
    (args.output / 'index.html').write_text('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>奶点记 1.1.0 截图审查</title><style>body{margin:32px;background:#ede8df;font:16px "Microsoft YaHei",sans-serif;color:#4d3a2c}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:24px}figure{margin:0}img{display:block;width:100%;height:auto}figcaption{padding:12px 0}h1{font-size:24px}</style><h1>奶点记 1.1.0（5）· 应用介绍截图</h1><p>1080×1920 · 应用区域 864×1536 · 统一位置 (108,336) · 统一圆角 52px · 虚构演示数据</p><main>'+cards+'</main></html>', encoding='utf-8')
    print(json.dumps({'count': len(entries), 'output': str(args.output), 'allViewportsIdentical': True}, ensure_ascii=False))


if __name__ == '__main__':
    main()
