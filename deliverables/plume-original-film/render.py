#!/usr/bin/env python3
"""Original Plume film. Only Pillow, NumPy and FFmpeg required. No input media."""
from pathlib import Path
from functools import lru_cache
import math, subprocess, wave, json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
W,H,FPS,DURATION = 1920,1080,30,42
INK='#242721'; PAPER='#F3F0E8'; WHITE='#FFFEFA'; MUTED='#777C70'
CORAL='#D87352'; GREEN='#55705C'; LINE='#D9DCD0'; DARK='#202A25'

def clamp(x): return max(0.,min(1.,x))
def ease(x): x=clamp(x); return 1-(1-x)**3
def smooth(x): x=clamp(x); return x*x*(3-2*x)
def mix(a,b,t): return a+(b-a)*t
@lru_cache(None)
def font(size,style='sans'):
    p={'sans':'/System/Library/Fonts/STHeiti Light.ttc','bold':'/System/Library/Fonts/STHeiti Medium.ttc','serif':'/System/Library/Fonts/Supplemental/Georgia.ttf','italic':'/System/Library/Fonts/Supplemental/Georgia Italic.ttf','mono':'/System/Library/Fonts/Menlo.ttc'}[style]
    return ImageFont.truetype(p,size)
@lru_cache(2048)
def glyph(text,size,color,style):
    f=font(size,style); b=f.getbbox(text); im=Image.new('RGBA',(max(1,b[2]-b[0]+4),max(1,b[3]-b[1]+6)))
    ImageDraw.Draw(im).text((2-b[0],2-b[1]),text,font=f,fill=color)
    return im
def txt(im,text,x,y,size=32,color=INK,style='sans',alpha=1,center=False):
    g=glyph(text,size,color,style)
    if center:x-=g.width/2
    if alpha<1:g=g.copy();g.putalpha(g.getchannel('A').point(lambda a:int(a*clamp(alpha))))
    im.paste(g,(int(x),int(y)),g)
def rr(im,box,fill,r=20,outline=None,width=1):ImageDraw.Draw(im).rounded_rectangle(tuple(map(int,box)),r,fill=fill,outline=outline,width=width)
def line(im,pts,fill=LINE,width=2):ImageDraw.Draw(im).line(pts,fill=fill,width=width)
def pill(im,label,x,y,fill=WHITE,color=INK,size=23):
    w=glyph(label,size,color,'sans').width+42;rr(im,(x,y,x+w,y+48),fill,24);txt(im,label,x+20,y+12,size,color);return w
def reveal(im,text,x,y,t,delay=0,size=80,color=INK,style='bold',center=False):
    p=ease((t-delay)/.85);txt(im,text,x,y+30*(1-p),size,color,style,p,center)
def feather(im,x,y,scale=1,color=CORAL):
    d=ImageDraw.Draw(im);pts=[]
    for i in range(70):
        u=i/69; pts.append((x+scale*(120*u+34*math.sin(math.pi*u)),y+scale*(-130*u+30*math.sin(math.pi*u))))
    for i in range(69,-1,-1):
        u=i/69;pts.append((x+scale*(120*u-23*math.sin(math.pi*u)),y+scale*(-130*u-18*math.sin(math.pi*u))))
    d.polygon(pts,fill=color);line(im,[(x-12*scale,y+18*scale),(x+103*scale,y-111*scale)],PAPER,max(2,int(3*scale)))
def base(n,t,dark=False):
    im=Image.new('RGB',(W,H),DARK if dark else PAPER)
    d=ImageDraw.Draw(im)
    c='#29342E' if dark else '#EAE9E0'
    for x in range(-200,2200,110):d.line([(x+int(t*4)%110,0),(x+int(t*4)%110,H)],fill=c)
    for y in range(0,H,110):d.line([(0,y),(W,y)],fill=c)
    txt(im,'Plume',94,57,36,WHITE if dark else INK,'serif')
    txt(im,'给想法，一个自己的地方。',1295,66,24,'#B9C4BA' if dark else MUTED)
    line(im,[(96,124),(1824,124)],'#465348' if dark else LINE)
    txt(im,f'0{n+1} / 07',96,1005,20,'#B9C4BA' if dark else MUTED,'mono')
    txt(im,'MARKDOWN  /  AI  /  macOS',1390,1005,20,'#B9C4BA' if dark else MUTED,'mono')
    line(im,[(96,974),(1824,974)],'#465348' if dark else LINE)
    line(im,[(96,974),(96+1728*(n*6+t)/42,974)],CORAL,3)
    return im

def note_card(title,body,w=380,h=250):
    im=Image.new('RGBA',(w+40,h+40));rr(im,(20,25,w+20,h+25),'#00000016',22)
    rr(im,(12,10,w+12,h+10),WHITE,18,LINE)
    txt(im,'.md',34,32,20,CORAL,'mono');txt(im,title,34,82,32,INK,'bold')
    for i,s in enumerate(body):txt(im,s,34,141+i*35,22,MUTED)
    return im

def shell(im,x,y,w,h,label='灵感 / 一次关于写作的思考'):
    rr(im,(x+8,y+14,x+w+8,y+h+14),'#E0E0D5',26)
    rr(im,(x,y,x+w,y+h),WHITE,24,LINE)
    line(im,[(x,y+65),(x+w,y+65)],LINE)
    for i,c in enumerate(['#DE8475','#E2BC69','#8EAF8E']):ImageDraw.Draw(im).ellipse((x+26+i*26,y+26,x+38+i*26,y+38),fill=c)
    txt(im,label,x+w/2,y+24,22,MUTED,center=True)

def scene0(t):
    im=base(0,t);p=ease(t/1.4)
    cards=[('一闪而过的念头',['先记下来。','也许，明天会用到。'],-8,125,222),('读书摘录',['值得反复咀嚼的一句话。','还有，我自己的理解。'],7,1395,210),('还没写完的计划',['一个开始。','一些等待连接的线索。'],5,250,663),('今天的灵感',['让零散的想法，','慢慢长成自己的答案。'],-7,1290,652)]
    for j,(title,body,a,x,y) in enumerate(cards):
        card=note_card(title,body,340,224).rotate(a+math.sin(t*.6+j)*1.5,resample=Image.Resampling.BICUBIC,expand=True)
        im.paste(card,(int(x+(1-p)*(x-960)*.3),int(y+math.sin(t+j)*8)),card)
    reveal(im,'好想法，',960,365,t,.15,96,center=True)
    reveal(im,'值得有个好归处。',960,497,t,.65,96,center=True)
    reveal(im,'从一行笔记，到下一次创造。',960,631,t,1.3,30,MUTED,'sans',True)
    return im

def scene1(t):
    im=base(1,t);reveal(im,'落笔，就进入心流。',960,183,t,0,70,center=True)
    reveal(im,'Markdown 写作 · 清晰，也轻盈',960,277,t,.25,28,MUTED,'sans',True)
    x,y,w,h=250,368+int(55*(1-ease(t/.9))),1420,540
    shell(im,x,y,w,h)
    rr(im,(x+14,y+78,x+245,y+h-14),'#F0F1E9',12)
    txt(im,'我的笔记',x+38,y+105,24,MUTED)
    for i,s in enumerate(['灵感','关于写作的思考','阅读笔记','项目计划']):
        if i==1:rr(im,(x+25,y+178,x+231,y+227),'#E1E5D8',10)
        txt(im,s,x+38,y+150+i*55,21,INK)
    tx=x+303;txt(im,'一次关于写作的思考',tx,y+122,46,INK,'bold')
    txt(im,'先写下来，想法才有了形状。',tx,y+218,30,INK)
    sentence='把脑海里的片段，慢慢写成清晰的表达。'
    count=int(clamp((t-1.3)/2.7)*len(sentence));txt(im,sentence[:count],tx,y+278,30,INK)
    tw=glyph(sentence[:count],30,INK,'sans').width if count else 0
    if t%1<.65:line(im,[(tx+tw+5,y+279),(tx+tw+5,y+313)],CORAL,3)
    a=ease((t-3.8)/.6);txt(im,'让注意力，留在文字本身。',tx,y+383,25,MUTED,alpha=a)
    txt(im,'产品界面示意',x+w-166,y+h-36,17,MUTED)
    return im

def scene2(t):
    im=base(2,t,True)
    reveal(im,'笔记在本地。',115,273,t,0,82,WHITE)
    reveal(im,'灵感属于你。',115,386,t,.35,82,WHITE)
    reveal(im,'一个文件夹，一份份 Markdown。',118,540,t,.75,30,'#B9C4BA','sans')
    reveal(im,'直接编辑磁盘文件，保留熟悉的工作方式。',118,596,t,1.1,26,'#B9C4BA','sans')
    pill(im,'.md',120,719,'#354B3C','#E1E6D9');pill(im,'本地文件',237,719,'#354B3C','#E1E6D9')
    for j,(name,sub) in enumerate([('灵感.md','今天的念头，明天的起点。'),('阅读.md','记录，也连接自己的理解。'),('计划.md','把下一步，写得更清楚。')]):
        p=ease((t-.4-j*.35)/1.2);x=1020+j*44+int(180*(1-p));y=243+j*157+math.sin(t*.9+j)*7
        card=note_card(name,[sub],590,238);im.paste(card,(int(x),int(y)),card)
    return im

def scene3(t):
    im=base(3,t)
    reveal(im,'让 AI 接住',110,254,t,0,77)
    reveal(im,'你的下一句。',110,361,t,.3,77)
    reveal(im,'Claude Code 与 Codex',113,511,t,.55,29,CORAL,'sans')
    reveal(im,'和你在同一个笔记库里工作。',113,565,t,.8,29,MUTED,'sans')
    pill(im,'同一份文件 · 同一份上下文',114,700,'#E2E6DA',GREEN,24)
    x,y,w,h=885,208,925,690;shell(im,x,y,w,h,'Agent / 写作伙伴')
    pill(im,'Claude Code',x+36,y+99,'#F1E0D5',CORAL);pill(im,'Codex',x+247,y+99,'#E6E9E0',INK)
    rr(im,(x+35,y+182,x+w-35,y+295),'#EEF0E7',18)
    request='请把这些灵感，整理成一段清晰的开头。';n=int(clamp((t-.5)/1.5)*len(request))
    txt(im,request[:n],x+60,y+218,27)
    if t>2:
        a=ease((t-2)/.5);txt(im,'整理思路，延续你的表达',x+47,y+344,30,INK,'bold',a)
        lines=['每一个想法，都值得被认真记录。','从零散的片段出发，我们逐渐看见','问题的轮廓，也找到自己的表达。']
        for j,s in enumerate(lines):
            n=int(clamp((t-2.3-j*.5)/.75)*len(s));txt(im,s[:n],x+49,y+413+j*49,28,MUTED)
    if t>4.2:pill(im,'笔记已更新 · 可审阅改动',x+46,y+588,'#E5EBDE',GREEN,22)
    txt(im,'产品界面示意',x+w-168,y+h-34,17,MUTED)
    return im

def scene4(t):
    im=base(4,t);reveal(im,'AI 可以改。决定权在你。',960,177,t,0,72,center=True)
    reveal(im,'每一处改动，都能审阅、接受或还原。',960,278,t,.4,29,MUTED,'sans',True)
    x,y,w,h=295,389,1330,478;shell(im,x,y,w,h,'审阅改动 / 灵感.md')
    accepted=t>3.7
    rr(im,(x+36,y+103,x+w-36,y+185),'#F5E7E1',14)
    txt(im,'−   想法很多，但还不知道从哪里开始。',x+61,y+128,31,'#A56454')
    if accepted:line(im,[(x+116,y+148),(x+61+glyph('−   想法很多，但还不知道从哪里开始。',31,'#A56454','sans').width,y+148)],'#A56454',2)
    p=ease((t-.8)/.8)
    rr(im,(x+36,y+205,x+w-36,y+327),'#E5EDDF',14)
    txt(im,'+   从一个想法开始，让表达逐渐清晰。',x+61,y+250+20*(1-p),31,GREEN,alpha=p)
    txt(im,'改动 1',x+41,y+387,25,MUTED)
    pill(im,'还原',x+w-282,y+371,'#EDEFE7',MUTED,24)
    pill(im,'已接受' if accepted else '接受',x+w-158,y+371,GREEN,WHITE,24)
    if 2.6<t<4.3:
        p=ease((t-2.6)/.9);cx=mix(1460,1500,p);cy=mix(922,792,p)
        ImageDraw.Draw(im).polygon([(cx,cy),(cx+3,cy+38),(cx+13,cy+28),(cx+24,cy+28)],fill=INK)
        if 3.65<t<4.1:
            r=15+(t-3.65)*80;ImageDraw.Draw(im).ellipse((cx-r,cy-r,cx+r,cy+r),outline=CORAL,width=3)
    txt(im,'产品界面示意',x+w-170,y+h-28,17,MUTED)
    return im

def scene5(t):
    im=base(5,t);reveal(im,'把世界调轻。',960,188,t,0,76,center=True)
    reveal(im,'把注意力，留给这一行。',960,293,t,.4,45,MUTED,'sans',True)
    x,y,w,h=360,419,1200,440;shell(im,x,y,w,h,'专注写作')
    fade=1-.76*smooth((t-.8)/1.4)
    txt(im,'灵感来自阅读，也来自生活中很小的瞬间。',960,y+121,30,MUTED,alpha=fade,center=True)
    rr(im,(x+100,y+186,x+w-100,y+264),'#EFF0E7',14)
    s='此刻，只需要写好下一句话。';n=int(clamp((t-.7)/2.4)*len(s));txt(im,s[:n],960,y+207,39,INK,center=True)
    txt(im,'写下去，答案会在文字中慢慢浮现。',960,y+304,30,MUTED,alpha=fade,center=True)
    txt(im,'产品界面示意',x+w-168,y+h-30,17,MUTED)
    return im

def scene6(t):
    im=base(6,t,True);p=ease(t/1.4)
    # A quiet, expanding orbit closes the scattered-note motif.
    d=ImageDraw.Draw(im)
    for j in range(3):
        r=260+j*115+22*p;d.ellipse((960-r,500-r*.72,960+r,500+r*.72),outline='#35463A',width=2)
    feather(im,910,298,0.9)
    reveal(im,'Plume',960,332,t,.15,170,WHITE,'serif',True)
    reveal(im,'让想法，落在自己的纸上。',960,565,t,.6,59,WHITE,'bold',True)
    reveal(im,'本地 Markdown  /  AI 协作  /  专注写作',960,681,t,1.1,28,'#B9C4BA','sans',True)
    p=ease((t-1.9)/.65)
    rr(im,(802,785+int(20*(1-p)),1118,855+int(20*(1-p))),CORAL,35)
    txt(im,'从下一行开始',960,807+int(20*(1-p)),29,WHITE,center=True,alpha=p)
    return im

SCENES=[scene0,scene1,scene2,scene3,scene4,scene5,scene6]
def frame(t):
    n=min(6,int(t/6));u=t-n*6;im=SCENES[n](u)
    if n>0 and u<.45:im=Image.blend(SCENES[n-1](6+u),im,smooth(u/.45))
    if t<.35:im=Image.blend(Image.new('RGB',(W,H),PAPER),im,smooth(t/.35))
    return im

def soundtrack():
    sr=48000;length=int(DURATION*sr);audio=np.zeros((length,2),np.float64);rng=np.random.default_rng(41)
    def add(sig,start,pan=0):
        i=int(start*sr);end=min(length,i+len(sig));sig=sig[:end-i]
        if len(sig):audio[i:end,0]+=sig*math.sqrt((1-pan)/2);audio[i:end,1]+=sig*math.sqrt((1+pan)/2)
    def note(freq,seconds,kind='pad'):
        t=np.arange(int(seconds*sr))/sr
        if kind=='pad':
            env=np.minimum(t/1.2,1)*np.minimum((seconds-t)/1.7,1)
            return .025*env*(np.sin(2*np.pi*freq*t)+.35*np.sin(2*np.pi*(freq*1.002)*t)+.16*np.sin(4*np.pi*freq*t))
        return .072*(1-np.exp(-t*80))*np.exp(-t*3.2)*(np.sin(2*np.pi*freq*t)+.22*np.sin(4*np.pi*freq*t))
    chords=[[50,57,60,65],[46,53,57,60],[53,60,64,69],[48,55,60,64],[50,57,62,65],[46,53,57,62],[53,60,65,69]]
    for k,ch in enumerate(chords):
        for j,m in enumerate(ch):add(note(440*2**((m-69)/12),7.2),k*6,(j-1.5)*.33)
        for b in range(10):
            m=ch[[0,2,1,3,2,1,3,2,1,2][b]]+12;add(note(440*2**((m-69)/12),1.7,'pluck'),k*6+b*.6,(b%3-1)*.45)
    for st in np.arange(6,36,.6):
        t=np.arange(int(.23*sr))/sr;phase=2*np.pi*(48*t+50*(1-np.exp(-t*25))/25)
        add(.055*np.sin(phase)*np.exp(-t*22),st)
        if int(round(st/.6))%2:
            t=np.arange(int(.10*sr))/sr;noise=rng.standard_normal(len(t));noise=np.diff(noise,prepend=0)
            add(.01*noise*np.exp(-t*55),st+.3,.2)
    for st in [6,12,18,24,30,36]:
        t=np.arange(int(.75*sr))/sr;noise=rng.standard_normal(len(t));noise=np.convolve(noise,np.ones(55)/55,'same')
        add(.04*noise*np.sin(np.pi*t/.75)**2,st-.35,-.3)
    ts=np.arange(length)/sr;fade=np.minimum(ts/1.8,1)*np.minimum((DURATION-ts)/2.4,1);audio*=fade[:,None]
    audio*=.78/max(.01,np.abs(audio).max())
    with wave.open(str(ROOT/'original-score.wav'),'wb') as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr);f.writeframes((audio*32767).astype('<i2').tobytes())

def stills():
    sheet=Image.new('RGB',(1440,4*435),PAPER)
    times=[3.5,10.8,15.2,23.3,28.8,34.7,40]
    for i,t in enumerate(times):
        im=frame(t);im.save(ROOT/f'scene-{i+1:02d}.jpg',quality=94)
        thumb=im.resize((720,405),Image.Resampling.LANCZOS);x=(i%2)*720;y=(i//2)*435;sheet.paste(thumb,(x,y));txt(sheet,f'{t:04.1f}s',x+15,y+411,18,MUTED,'mono')
    sheet.save(ROOT/'storyboard.jpg',quality=92);frame(40).save(ROOT/'cover.jpg',quality=96)

def render():
    soundtrack();stills()
    cmd=['ffmpeg','-hide_banner','-loglevel','warning','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{W}x{H}','-framerate',str(FPS),'-i','pipe:0','-i',str(ROOT/'original-score.wav'),'-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-ar','48000','-af','loudnorm=I=-16:TP=-1.5:LRA=9','-t',str(DURATION),'-movflags','+faststart',str(ROOT/'Plume-让想法落在自己的纸上.mp4')]
    p=subprocess.Popen(cmd,stdin=subprocess.PIPE)
    for i in range(FPS*DURATION):
        p.stdin.write(frame(i/FPS).tobytes())
        if i%180==0:print(f'Rendered {i}/{FPS*DURATION} frames',flush=True)
    p.stdin.close();ret=p.wait()
    if ret:raise RuntimeError(f'ffmpeg exited {ret}')
    print('Render complete',flush=True)

if __name__=='__main__':
    if '--stills' in sys.argv:stills()
    else:render()
