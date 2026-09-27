# Abstract marks, round 5: more geometric forms. Each one says "two, making one".
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
def g(id, a, b, x2=1, y2=1):
    return f'<linearGradient id="{id}" x1="0" y1="0" x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>'
def svg(bg, defs, body, rim=0.25):
    return (f'{HEAD}<defs>{g("bg", *bg, x2=0.4)}{defs}</defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>{body}'
            f'<rect x="101.5" y="101.5" width="821" height="821" rx="184" fill="none" stroke="#fff" stroke-opacity="{rim}" stroke-width="3"/></svg>')
LIGHT, DARKRIM = 0.9, 0.2
out = {}

# A · 二：中文的"二"，两横，一短一长
out["A"] = svg(("#5E6BFF", "#2B2FCF"), g("w", "#FFFFFF", "#E3E7FF"),
  '''<rect x="340" y="372" width="344" height="92" rx="46" fill="url(#w)"/>
  <rect x="262" y="560" width="500" height="92" rx="46" fill="#FFFFFF" fill-opacity="0.5"/>''')

# B · 拼方：两个三角沿对角线错开，合起来是一个方
out["B"] = svg(("#FFFFFF", "#ECEEF2"), g("k", "#2B2D33", "#050507") + g("b", "#4D8BFF", "#1F4FE0"),
  '''<g stroke-linejoin="round" stroke-width="28">
  <path d="M290 290 L700 290 L290 700 Z" fill="url(#k)" stroke="url(#k)"/>
  <path d="M734 324 L734 734 L324 734 Z" fill="url(#b)" stroke="url(#b)"/></g>''', rim=LIGHT)

# C · 半圆：两个半圆一左一右、一上一下，错成一个 S
out["C"] = svg(("#0F3B2F", "#041A14"), g("m", "#6FF2B8", "#1FB57E") + g("w", "#FFFFFF", "#DDEFE6"),
  '''<path d="M512 222 A160 160 0 0 1 512 542 Z" fill="url(#m)"/>
  <path d="M512 482 A160 160 0 0 0 512 802 Z" fill="url(#w)"/>''', rim=DARKRIM)

# D · 方与圆：一个方（人）一个圆（agent），交叠处是第三种颜色
out["D"] = svg(("#F5F6F8", "#E3E6EC"), g("k", "#26282E", "#0A0B0D") + g("b", "#43C6FF", "#1D7BFF") +
  '<clipPath id="c"><circle cx="630" cy="630" r="176"/></clipPath>',
  '''<rect x="244" y="244" width="340" height="340" rx="64" fill="url(#k)"/>
  <circle cx="630" cy="630" r="176" fill="url(#b)"/>
  <g clip-path="url(#c)"><rect x="244" y="244" width="340" height="340" rx="64" fill="#BDEBFF"/></g>''', rim=LIGHT)

# E · W：两个 V 交错成 Twain 的 W
out["E"] = svg(("#1A1F4D", "#090B22"), g("c", "#7AF0FF", "#2FB3FF") + g("v", "#C59BFF", "#8150FF"),
  '''<g fill="none" stroke-width="92" stroke-linecap="round" stroke-linejoin="round">
  <path d="M256 340 L384 684 L512 340" stroke="url(#c)"/>
  <path d="M512 340 L640 684 L768 340" stroke="url(#v)" style="mix-blend-mode:screen"/></g>''', rim=DARKRIM)

# F · 相握：两个 L 互相咬合成一个方框
out["F"] = svg(("#FFFFFF", "#ECEEF2"), g("k", "#2B2D33", "#050507") + g("r", "#FF6B6B", "#E8364F"),
  '''<g fill="none" stroke-width="96" stroke-linecap="round" stroke-linejoin="round">
  <path d="M320 612 L320 320 L612 320" stroke="url(#k)"/>
  <path d="M412 704 L704 704 L704 412" stroke="url(#r)"/></g>''', rim=LIGHT)

# G · 对角扇：两片四分之一圆对角相接，像一对风车叶
out["G"] = svg(("#2A1660", "#100828"), g("p", "#FF9EC4", "#FF4F93") + g("v", "#A99BFF", "#6A4BFF"),
  '''<path d="M500 500 L500 220 A280 280 0 0 1 780 500 Z" fill="url(#p)"/>
  <path d="M524 524 L524 804 A280 280 0 0 1 244 524 Z" fill="url(#v)"/>''', rim=DARKRIM)

# H · 双菱：两个菱形并排重叠，中间透出一颗小菱形
out["H"] = svg(("#E9FBF8", "#CFF1EC"), g("t", "#2FD6B6", "#0A9F8C") + g("b", "#3F7CFF", "#2447D6") +
  '<clipPath id="d"><rect x="-150" y="-150" width="300" height="300" rx="36" transform="translate(604 512) rotate(45)"/></clipPath>',
  '''<rect x="-150" y="-150" width="300" height="300" rx="36" fill="url(#t)" transform="translate(420 512) rotate(45)"/>
  <rect x="-150" y="-150" width="300" height="300" rx="36" fill="url(#b)" transform="translate(604 512) rotate(45)"/>
  <g clip-path="url(#d)"><rect x="-150" y="-150" width="300" height="300" rx="36" fill="#FFFFFF" transform="translate(420 512) rotate(45)"/></g>''', rim=LIGHT)

for k, s in out.items():
    open(f"drafts5/{k}.svg", "w").write(s)
