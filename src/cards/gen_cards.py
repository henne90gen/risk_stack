#!/usr/bin/env python3
"""Generates one SVG per Flip 7 card into the current directory."""

import os

W, H = 250, 350
R = 18  # corner radius

# Distinct color per number card (bright, playful palette)
NUMBER_COLORS = {
    0: "#8e44ad",
    1: "#e74c3c",
    2: "#e67e22",
    3: "#f1c40f",
    4: "#2ecc71",
    5: "#1abc9c",
    6: "#3498db",
    7: "#9b59b6",
    8: "#e84393",
    9: "#d35400",
    10: "#16a085",
    11: "#2980b9",
    12: "#c0392b",
}

MODIFIER_COLOR = "#f39c12"
X2_COLOR = "#e67e22"
ACTION_COLORS = {
    "freeze": "#5dade2",
    "flip_three": "#af7ac5",
    "second_chance": "#ec7063",
}


def card_svg(bg, main_text, corner_text, main_size=140, sub_text=None):
    corner = (
        f'<text x="24" y="46" font-family="Arial, sans-serif" font-size="30" '
        f'font-weight="bold" fill="#ffffff">{corner_text}</text>'
        f'<text x="24" y="46" font-family="Arial, sans-serif" font-size="30" '
        f'font-weight="bold" fill="#ffffff" '
        f'transform="rotate(180 {W / 2} {H / 2})">{corner_text}</text>'
    )
    main_y = H // 2 + (0 if sub_text else main_size // 3)
    if sub_text:
        main_y = H // 2 - 10
    main = (
        f'<text x="{W // 2}" y="{main_y}" font-family="Arial, sans-serif" '
        f'font-size="{main_size}" font-weight="bold" fill="#ffffff" '
        f'text-anchor="middle" stroke="#00000030" stroke-width="3" '
        f'paint-order="stroke">{main_text}</text>'
    )
    sub = ""
    if sub_text:
        lines = sub_text.split(" ")
        # keep short labels on one line
        if len(sub_text) <= 8:
            lines = [sub_text]
        sub = "".join(
            f'<text x="{W // 2}" y="{H // 2 + 60 + i * 38}" font-family="Arial, sans-serif" '
            f'font-size="30" font-weight="bold" fill="#ffffff" '
            f'text-anchor="middle" letter-spacing="2">{line}</text>'
            for i, line in enumerate(lines)
        )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{bg}"/>
      <stop offset="1" stop-color="{bg}" stop-opacity="0.75"/>
    </linearGradient>
  </defs>
  <rect x="1" y="1" width="{W - 2}" height="{H - 2}" rx="{R}" fill="url(#bg)" stroke="#ffffff" stroke-width="2"/>
  <rect x="12" y="12" width="{W - 24}" height="{H - 24}" rx="{R - 6}" fill="none" stroke="#ffffff" stroke-width="3" stroke-opacity="0.5"/>
  <circle cx="{W // 2}" cy="{H // 2}" r="82" fill="#ffffff" fill-opacity="0.12"/>
  {corner}
  {main}
  {sub}
</svg>
'''


files = {}

# Number cards 0-12
for n in range(13):
    size = 140 if n < 10 else 120
    files[f"{n}.svg"] = card_svg(NUMBER_COLORS[n], str(n), str(n), size)

# Modifier cards
for n in (2, 4, 6, 8, 10):
    files[f"plus_{n}.svg"] = card_svg(MODIFIER_COLOR, f"+{n}", f"+{n}", 110, "BONUS")

files["x2.svg"] = card_svg(X2_COLOR, "\u00d72", "\u00d72", 110, "MULTIPLY")

# Action cards
files["freeze.svg"] = card_svg(ACTION_COLORS["freeze"], "\u2744", "F", 130, "FREEZE")
files["flip_three.svg"] = card_svg(ACTION_COLORS["flip_three"], "3\u21bb", "F3", 100, "FLIP THREE")
files["second_chance.svg"] = card_svg(ACTION_COLORS["second_chance"], "\u21ba", "SC", 130, "SECOND CHANCE")

for name, content in files.items():
    with open(os.path.join(os.path.dirname(__file__) or ".", name), "w") as f:
        f.write(content)

print(f"wrote {len(files)} card SVGs")
