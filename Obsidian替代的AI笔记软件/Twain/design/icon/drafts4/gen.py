# Abstract marks, round 4: new palettes, no brown.
import math
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
def grad(id, a, b, x2=1, y2=1):
    return f'<linearGradient id="{id}" x1="0" y1="0" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>'
def svg(bg, defs, body, rim=0.25):
    return (f'{HEAD}<defs><clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>'
            f'{grad("bg", *bg, x2=0.4)}{defs}</defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>{body}'
            f'<rect x="101.5" y="101.5" width="821" height="821" rx="184" fill="none" stroke="#fff" stroke-opacity="{rim}" stroke-width="3"/></svg>')

out = {}

# 1 · 汇流 · 深海蓝：白与青两股汇成一股
out["1"] = svg(("#1B2A6B", "#0A1030"),
  grad("a", "#FFFFFF", "#D6E2FF") + grad("b", "#7FE3FF", "#3C7BFF") +
  '<linearGradient id="stem" gradientUnits="userSpaceOnUse" x1="457" y1="0" x2="567" y2="0"><stop offset="0.1" stop-color="#FFFFFF"/><stop offset="0.9" stop-color="#4FA8FF"/></linearGradient>'
  '<linearGradient id="fade" gradientUnits="userSpaceOnUse" x1="0" y1="470" x2="0" y2="640"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>'
  '<mask id="fi" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="url(#fade)"/></mask>',
  '''<g clip-path="url(#tile)" fill="none" stroke-width="110" stroke-linecap="round">
  <path d="M292 40 C292 330 512 420 512 640 L512 1000" stroke="url(#a)"/>
  <path d="M732 40 C732 330 512 420 512 640 L512 1000" stroke="url(#b)"/>
  <path d="M512 430 L512 1000" stroke="url(#stem)" mask="url(#fi)"/></g>''', rim=0.2)

# 2 · 交集 · 玻璃：浅底上两片彩色玻璃，重叠处最亮
out["2"] = svg(("#FFFFFF", "#E9EDF5"),
  grad("a", "#6AA8FF", "#2F5BFF") + grad("b", "#C58BFF", "#7B3CFF") +
  '<clipPath id="lens"><circle cx="624" cy="512" r="220"/></clipPath>'
  '<linearGradient id="glow" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E9F1FF"/><stop offset="1" stop-color="#B9C6FF"/></linearGradient>'
  '<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="20" stdDeviation="26" flood-color="#2B2F6B" flood-opacity="0.25"/></filter>',
  '''<g transform="rotate(-35 512 512)" filter="url(#sh)">
  <circle cx="400" cy="512" r="220" fill="url(#a)"/>
  <circle cx="624" cy="512" r="220" fill="url(#b)"/>
  <g clip-path="url(#lens)"><circle cx="400" cy="512" r="220" fill="url(#glow)"/></g></g>''', rim=0.9)

# 3 · 错位 · 黑白：纯白底，一黑一灰两半
out["3"] = svg(("#FFFFFF", "#ECECEE"),
  grad("a", "#2A2A2E", "#000000") + grad("b", "#B9BCC6", "#8A8E9B"),
  '''<path d="M506 216 A280 280 0 0 0 506 776 Z" fill="url(#a)" transform="translate(-10 -46)"/>
  <path d="M518 248 A280 280 0 0 1 518 808 Z" fill="url(#b)" transform="translate(10 -6)"/>''', rim=0.9)

# 4 · 叠影 · 紫粉：两个圆角方块旋转叠合，重叠处透出第三色
A4 = '<rect x="250" y="250" width="320" height="320" rx="80" transform="rotate(-10 410 410)"/>'
B4 = '<rect x="454" y="454" width="320" height="320" rx="80" transform="rotate(12 614 614)"/>'
out["4"] = svg(("#2A1B5E", "#120B2E"),
  grad("a", "#FF9CBB", "#FF5C8A") + grad("b", "#9A89FF", "#5B3DF5") + f'<clipPath id="ov">{B4}</clipPath>',
  f'''<g fill="url(#a)">{A4}</g><g fill="url(#b)">{B4}</g>
  <g clip-path="url(#ov)" fill="#FFE3EE">{A4}</g>''')

# 5 · 双弧 · 薄荷：两道弧各占半圈，合成一个开口的圆
out["5"] = svg(("#E8FBF4", "#C9F0E2"),
  grad("a", "#1ECB9A", "#0E8F7A") + grad("b", "#0F3D3A", "#062422"),
  '''<g fill="none" stroke-width="120" stroke-linecap="round">
  <path d="M512 232 A280 280 0 0 0 272 656" stroke="url(#b)" transform="rotate(-8 512 512)"/>
  <path d="M512 792 A280 280 0 0 0 752 368" stroke="url(#a)" transform="rotate(-8 512 512)"/></g>''', rim=0.9)

# 6 · 两点一线 · 靛蓝：共笔 · Twain 中间那个点——两个点被一条线连起来
out["6"] = svg(("#5B6CFF", "#2B2FD9"),
  grad("a", "#FFFFFF", "#DDE3FF"),
  '''<line x1="330" y1="600" x2="694" y2="424" stroke="#fff" stroke-opacity="0.55" stroke-width="44" stroke-linecap="round"/>
  <circle cx="330" cy="600" r="118" fill="url(#a)"/>
  <circle cx="694" cy="424" r="118" fill="#0E1260"/>''')

for k, s in out.items():
    open(f"drafts4/{k}.svg", "w").write(s)
