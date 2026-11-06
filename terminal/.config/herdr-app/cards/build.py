"""Builds Rex-style program cards from Herdr's program table and glyphs.

Run after a Herdr update to pick up new programs:
    python3 ~/.config/herdr-app/cards/build.py
"""
import json
import re
import subprocess
from pathlib import Path

HOME = Path(__file__).resolve().parent.parent
APP = Path.home() / "Applications/Herdr.app/Contents/MacOS/Herdr"

# Rex draws Claude as a white glyph on an orange card.
OVERRIDES = {"claude": {"tile": "#d97757", "color": "#ffffff", "tint": True}}


def program_table():
    text = subprocess.run(["strings", "-n", "20", str(APP)], capture_output=True, text=True).stdout
    table = {}
    for line in text.splitlines():
        if re.match(r'^\s*"[a-z0-9._-]+": \{"name":"[^"]*","icon":"icons/', line):
            try:
                table.update(json.loads("{" + line.strip().rstrip(",") + "}"))
            except json.JSONDecodeError:
                pass
    return table


def mix(hex_color, target, amount):
    rgb = [int(hex_color[i : i + 2], 16) for i in (1, 3, 5)]
    end = 255 if target == "white" else 0
    return "#" + "".join(f"{round(c + (end - c) * amount):02x}" for c in rgb)


def glyph(svg_text, tint, color):
    root = re.search(r"<svg\b([^>]*)>", svg_text, re.S)
    body = svg_text[root.end() : svg_text.rindex("</svg>")]
    attrs = re.sub(r'\s(width|height|style|class|role)="[^"]*"', "", root.group(1))
    if tint:
        # Single-color glyphs take the card's color, however they paint.
        body = re.sub(r'(fill|stroke)="(?!none)[^"]*"', rf'\1="{color}"', body)
        attrs = re.sub(r'(fill|stroke)="(?!none)[^"]*"', rf'\1="{color}"', attrs)
    size, offset = 36, 14
    return f'<g fill="{color if tint else "currentColor"}" color="{color}"><svg x="{offset}" y="{offset}" width="{size}" height="{size}"{attrs}>{body}</svg></g>'


def card(key, program):
    tile = program["tile"]
    dark = sum(int(tile[i : i + 2], 16) for i in (1, 3, 5)) < 150
    top = mix(tile, "white", 0.22 if dark else 0.16)
    bottom = mix(tile, "black", 0.0 if dark else 0.1)
    icon = (HOME / program["icon"]).read_text()
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
<defs>
<linearGradient id="fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.38"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0.08"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.04"/></linearGradient>
</defs>
<rect x="0" y="0" width="64" height="64" rx="15" fill="url(#fill)"/>
<rect x="0.75" y="0.75" width="62.5" height="62.5" rx="14.25" fill="none" stroke="url(#edge)" stroke-width="1.5"/>
{glyph(icon, program.get("tint"), program.get("color", "#ffffff"))}
</svg>
'''


def main():
    table = program_table()
    for key, program in table.items():
        program = {**program, **OVERRIDES.get(key, {})}
        if not program.get("tile") or not (HOME / program["icon"]).exists():
            continue
        (HOME / "cards" / f"{key}.svg").write_text(card(key, program))
    print(f"{len(list((HOME / 'cards').glob('*.svg')))} cards")


main()
