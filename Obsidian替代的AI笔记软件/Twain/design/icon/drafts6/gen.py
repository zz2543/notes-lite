# Round 6: monochrome Liquid Glass. Two pieces of glass; where they overlap, the glass thickens.
import sys
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'

def filters(dark):
    return f'''
<filter id="bevel" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
  <feGaussianBlur in="SourceAlpha" stdDeviation="16" result="b"/>
  <feSpecularLighting in="b" surfaceScale="9" specularConstant="1.1" specularExponent="28" lighting-color="#fff" result="s">
    <feDistantLight azimuth="235" elevation="38"/></feSpecularLighting>
  <feComposite in="s" in2="SourceAlpha" operator="in" result="si"/>
  <feSpecularLighting in="b" surfaceScale="9" specularConstant="0.6" specularExponent="18" lighting-color="#fff" result="s2">
    <feDistantLight azimuth="55" elevation="30"/></feSpecularLighting>
  <feComposite in="s2" in2="SourceAlpha" operator="in" result="si2"/>
  <feComposite in="si" in2="si2" operator="arithmetic" k2="1" k3="0.5" result="spec"/>
  <feComposite in="SourceGraphic" in2="spec" operator="arithmetic" k2="1" k3="{0.95 if dark else 0.9}"/>
</filter>
<filter id="rim" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="9"/></filter>
<filter id="refract" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>
<filter id="drop" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="28"/></filter>'''

def glass(k, shape, dark, behind=None):
    """shape: an SVG element string (no fill). behind: element ids to show refracted through this glass."""
    body_top, body_bot = (("#FFFFFF", 0.30), ("#FFFFFF", 0.07)) if dark else (("#FFFFFF", 0.80), ("#C3C8D2", 0.55))
    edge = "#FFFFFF"
    shadow = ("#000", 0.6) if dark else ("#1B1E2A", 0.32)
    refr = ""
    if behind:
        refr = (f'<g clip-path="url(#c{k})" filter="url(#refract)" transform="translate(-6 10)">' + "".join(f'<use href="#{b}"/>' for b in behind) + "</g>"
                f'<g clip-path="url(#c{k})" filter="url(#refract)">' + "".join(f'<use href="#{b}s" fill="{"#FFFFFF" if dark else "#8C93A3"}" fill-opacity="{0.16 if dark else 0.28}"/>' for b in behind) + "</g>")
    return f'''
<defs><clipPath id="c{k}">{shape.format(extra="")}</clipPath>
<linearGradient id="t{k}" x1="0" y1="0" x2="0.6" y2="1"><stop offset="0" stop-color="{body_top[0]}" stop-opacity="{body_top[1]}"/><stop offset="1" stop-color="{body_bot[0]}" stop-opacity="{body_bot[1]}"/></linearGradient>
<linearGradient id="e{k}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{edge}" stop-opacity="1"/><stop offset="0.45" stop-color="{edge}" stop-opacity="0.08"/><stop offset="1" stop-color="{edge}" stop-opacity="0.7"/></linearGradient></defs>
<g id="g{k}">
  <defs>{shape.format(extra=f'id="g{k}s"')}</defs>
  <g transform="translate(0 30)" opacity="{shadow[1]}" filter="url(#drop)">{shape.format(extra=f'fill="{shadow[0]}"')}</g>
  {refr}
  <g filter="url(#bevel)">{shape.format(extra=f'fill="url(#t{k})"')}</g>
  <g clip-path="url(#c{k})">
    <g filter="url(#rim)">{shape.format(extra=f'fill="none" stroke="#fff" stroke-opacity="{0.8 if dark else 1}" stroke-width="30"')}</g>
  </g>
  {shape.format(extra=f'fill="none" stroke="url(#e{k})" stroke-width="3"')}
</g>'''

def tile(dark, body):
    bg = ('<radialGradient id="bg" cx="0.5" cy="0.3" r="0.85"><stop offset="0" stop-color="#34353A"/><stop offset="1" stop-color="#030304"/></radialGradient>' if dark else
          '<radialGradient id="bg" cx="0.5" cy="0.3" r="0.85"><stop offset="0" stop-color="#FAFBFC"/><stop offset="1" stop-color="#C9CDD6"/></radialGradient>')
    return (f'{HEAD}<defs>{bg}{filters(dark)}<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath></defs>'
            f'<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>'
            f'<g clip-path="url(#tile)">{body}</g>'
            f'<rect x="101.5" y="101.5" width="821" height="821" rx="184" fill="none" stroke="#fff" stroke-opacity="{0.22 if dark else 0.9}" stroke-width="3"/></svg>')

FORMS = {
  # 两片圆玻璃斜向叠合
  "discs": ('<circle cx="428" cy="428" r="210" {extra}/>', '<circle cx="596" cy="596" r="210" {extra}/>'),
  # 两块圆角方玻璃错位叠放
  "tiles": ('<rect x="236" y="236" width="380" height="380" rx="96" {extra}/>', '<rect x="408" y="408" width="380" height="380" rx="96" {extra}/>'),
  # 一个圆切成两半，错开
  "halves": ('<path d="M500 206 A290 290 0 0 0 500 786 Z" {extra}/>', '<path d="M524 238 A290 290 0 0 1 524 818 Z" {extra}/>'),
  # 二：两条玻璃横
  "two": ('<rect x="318" y="330" width="388" height="150" rx="75" {extra}/>', '<rect x="232" y="544" width="560" height="150" rx="75" {extra}/>'),
}
for name, (a, b) in FORMS.items():
    for dark in (True, False):
        body = glass("a", a, dark) + glass("b", b, dark, behind=["ga"])
        open(f"drafts6/{name}-{'dark' if dark else 'light'}.svg", "w").write(tile(dark, body))
