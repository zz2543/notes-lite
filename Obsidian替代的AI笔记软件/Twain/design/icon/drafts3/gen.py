# Abstract marks for 共笔 · Twain — two becoming one.
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
COMMON = '''<clipPath id="tile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
<radialGradient id="dark" cx="0.5" cy="0.35" r="0.8"><stop offset="0" stop-color="#2F2925"/><stop offset="1" stop-color="#0D0C0B"/></radialGradient>
<linearGradient id="pearl" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#D9D1C7"/></linearGradient>
<linearGradient id="clay" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F7A77E"/><stop offset="1" stop-color="#C2582A"/></linearGradient>'''
RIM = '<rect x="101.5" y="101.5" width="821" height="821" rx="184" fill="none" stroke="#fff" stroke-opacity="0.14" stroke-width="3"/>'
TILE = '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#dark)"/>'
def svg(defs, body): return f'{HEAD}<defs>{COMMON}{defs}</defs>{TILE}{body}{RIM}</svg>'

# A · 汇流：两股线从两边来，汇成一股往下写
A = svg('''<linearGradient id="stem" gradientUnits="userSpaceOnUse" x1="457" y1="0" x2="567" y2="0"><stop offset="0.1" stop-color="#FBF7F2"/><stop offset="0.9" stop-color="#E07B48"/></linearGradient>
<linearGradient id="fade" gradientUnits="userSpaceOnUse" x1="0" y1="470" x2="0" y2="640"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient>
<mask id="fadein" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="url(#fade)"/></mask>''', '''
<g clip-path="url(#tile)" fill="none" stroke-width="110" stroke-linecap="round">
  <path d="M292 40 C292 330 512 420 512 640 L512 1000" stroke="url(#pearl)"/>
  <path d="M732 40 C732 330 512 420 512 640 L512 1000" stroke="url(#clay)"/>
  <path d="M512 430 L512 1000" stroke="url(#stem)" mask="url(#fadein)"/>
</g>''')

# B · 一笔：一条连续的笔画，从你的颜色写到 agent 的颜色
B = svg('''<linearGradient id="wave" gradientUnits="userSpaceOnUse" x1="272" y1="0" x2="752" y2="0"><stop offset="0.3" stop-color="#FBF7F2"/><stop offset="0.7" stop-color="#E07B48"/></linearGradient>''', '''
<path d="M272 512 A120 120 0 0 1 512 512 A120 120 0 0 0 752 512" fill="none" stroke="url(#wave)" stroke-width="150" stroke-linecap="round"/>''')

# C · 交集：两束光重叠，交集处最亮
C = svg('''<clipPath id="lens"><circle cx="624" cy="512" r="220"/></clipPath>
<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#FFF4EC"/><stop offset="1" stop-color="#F6B792"/></radialGradient>''', '''
<g transform="rotate(-35 512 512)">
  <circle cx="400" cy="512" r="220" fill="url(#pearl)"/>
  <circle cx="624" cy="512" r="220" fill="url(#clay)"/>
  <g clip-path="url(#lens)"><circle cx="400" cy="512" r="220" fill="url(#glow)"/></g>
</g>''')

# D · 错位：一个圆分成两半，错开又咬合
D = svg('', '''
<path d="M506 216 A280 280 0 0 0 506 776 Z" fill="url(#pearl)" transform="translate(-10 -46)"/>
<path d="M518 248 A280 280 0 0 1 518 808 Z" fill="url(#clay)" transform="translate(10 -6)"/>''')

for n, s in dict(A=A, B=B, C=C, D=D).items():
    open(f"drafts3/{n}.svg", "w").write(s)
