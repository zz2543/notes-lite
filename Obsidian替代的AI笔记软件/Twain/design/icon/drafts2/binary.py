# 双星：两颗星绕同一个质心运行，永远相对。generates drafts2/binary.svg
import math, random
CX, CY, TILT, FLAT = 512, 520, math.radians(-18), 0.40
R_OUT, R_IN = 318, 196
t_pearl, t_clay = math.radians(-40), math.radians(140)

def P(rx, t):
    x, y = rx*math.cos(t), rx*FLAT*math.sin(t)
    return CX + x*math.cos(TILT) - y*math.sin(TILT), CY + x*math.sin(TILT) + y*math.cos(TILT)

def trail(name, rx, t_head, span, color, width, n=240):
    """A fading comet tail: opaque grey segments in a mask (so overlaps don't stack), one colour fill."""
    segs = []
    for i in range(n):
        a, b = t_head + span*i/n, t_head + span*(i+1)/n
        (x1, y1), (x2, y2) = P(rx, a), P(rx, b)
        k = i/n
        v = int(255*(1-k)**1.7)
        segs.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="rgb({v},{v},{v})" '
                    f'stroke-width="{width*(1-0.8*k):.1f}" stroke-linecap="round"/>')
    mask = f'<mask id="{name}" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">' + "".join(reversed(segs)) + '</mask>'
    return mask, f'<rect x="0" y="0" width="1024" height="1024" fill="{color}" mask="url(#{name})"/>'

def orbit(rx, color, op):
    return (f'<ellipse cx="{CX}" cy="{CY}" rx="{rx}" ry="{rx*FLAT}" transform="rotate({math.degrees(TILT):.1f} {CX} {CY})" '
            f'fill="none" stroke="{color}" stroke-opacity="{op}" stroke-width="3"/>')

tp = trail("tp", R_OUT, t_pearl, math.radians(175), "#F6F1EB", 22)
tc = trail("tc", R_IN, t_clay, math.radians(175), "#EC8756", 26)
px, py = P(R_OUT, t_pearl); cx_, cy_ = P(R_IN, t_clay)
random.seed(11)
stars = "".join(f'<circle cx="{random.uniform(140,884):.0f}" cy="{random.uniform(140,884):.0f}" r="{random.choice([1.8,2.4])}" '
                f'fill="#FFF3E8" opacity="{random.uniform(0.12,0.35):.2f}"/>' for _ in range(22))

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
{tp[0]}{tc[0]}
<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
<radialGradient id="bg" cx="0.5" cy="0.42" r="0.75"><stop offset="0" stop-color="#2E2723"/><stop offset="1" stop-color="#0C0B0A"/></radialGradient>
<radialGradient id="bary" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFD9C2" stop-opacity="0.3"/><stop offset="1" stop-color="#FFD9C2" stop-opacity="0"/></radialGradient>
<radialGradient id="clay" cx="0.36" cy="0.32" r="0.72"><stop offset="0" stop-color="#FFD0B4"/><stop offset="0.5" stop-color="#E27C4B"/><stop offset="1" stop-color="#8E3814"/></radialGradient>
<radialGradient id="pearl" cx="0.36" cy="0.32" r="0.72"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#EEE7DE"/><stop offset="1" stop-color="#A39B91"/></radialGradient>
<radialGradient id="haloC" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#E8804E" stop-opacity="0.55"/><stop offset="1" stop-color="#E8804E" stop-opacity="0"/></radialGradient>
<radialGradient id="haloP" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.35"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
<g clip-path="url(#tile)">{stars}<circle cx="{CX}" cy="{CY}" r="200" fill="url(#bary)"/></g>
<rect x="101.5" y="101.5" width="821" height="821" rx="184" fill="none" stroke="#fff" stroke-opacity="0.14" stroke-width="3"/>
{orbit(R_OUT, "#F3EEE8", 0.13)}
{orbit(R_IN, "#E8804E", 0.2)}
{tp[1]}
{tc[1]}
<circle cx="{CX}" cy="{CY}" r="9" fill="#FFF3E8"/>
<circle cx="{px:.1f}" cy="{py:.1f}" r="150" fill="url(#haloP)"/>
<circle cx="{px:.1f}" cy="{py:.1f}" r="60" fill="url(#pearl)"/>
<circle cx="{cx_:.1f}" cy="{cy_:.1f}" r="190" fill="url(#haloC)"/>
<circle cx="{cx_:.1f}" cy="{cy_:.1f}" r="80" fill="url(#clay)"/>
</svg>'''
open("drafts2/binary.svg", "w").write(svg)
