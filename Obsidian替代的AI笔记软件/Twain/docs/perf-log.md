# 性能记录

`scripts/perf.sh` 每跑一次追加一节。只比较同一台机器、同一个库副本上的数字。

## baseline · ca1ca2a · 2026-09-29 01:14

```
vault notes=397 picks=44 dim=false
open n=44 median=67.8ms p90=79.3ms max=97.4ms
sidebar hide frames=169 dropped=2 longest=40.1ms
sidebar show frames=166 dropped=3 longest=63.6ms
agent hide frames=158 dropped=2 longest=41.1ms
agent show frames=159 dropped=1 longest=36.3ms
idle space worst=69.2ms stalls>16ms=6
idle note worst=48.8ms stalls>16ms=4
type 80665 chars n=80 median=3.8ms p90=11.0ms max=37.8ms
caret start n=30 median=0.2ms p90=0.3ms max=9.4ms
caret end n=30 median=0.2ms p90=0.2ms max=0.5ms
memory start=139MB end=174MB
done
```

## d2 vault service · ef736ad · 2026-09-29 01:35

```
vault notes=397 picks=44 dim=false
open n=44 median=80.5ms p90=101.1ms max=133.0ms
sidebar hide frames=170 dropped=1 longest=53.9ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=161 dropped=2 longest=52.5ms
agent show frames=160 dropped=3 longest=39.9ms
idle space worst=63.2ms stalls>16ms=4
idle note worst=40.8ms stalls>16ms=4
type 80665 chars n=80 median=10.6ms p90=21.1ms max=57.4ms
caret start n=30 median=0.2ms p90=0.3ms max=1.8ms
caret end n=30 median=0.1ms p90=0.1ms max=0.3ms
memory start=136MB end=166MB
done
```

## d1 no tick · c5d093d · 2026-09-29 01:46

```
vault notes=397 picks=44 dim=false
open n=44 median=74.6ms p90=91.9ms max=116.0ms
sidebar hide frames=168 dropped=3 longest=50.5ms
sidebar show frames=170 dropped=1 longest=50.9ms
agent hide frames=159 dropped=5 longest=40.4ms
agent show frames=154 dropped=5 longest=55.7ms
idle space worst=51.5ms stalls>16ms=4
idle note worst=42.3ms stalls>16ms=3
type 80665 chars n=80 median=12.4ms p90=25.1ms max=56.1ms
caret start n=30 median=0.1ms p90=0.2ms max=4.6ms
caret end n=30 median=0.1ms p90=0.1ms max=0.5ms
memory start=136MB end=177MB
done
```

## d1 guarded mutations · 67cd501 · 2026-09-29 09:54

```
vault notes=397 picks=44 dim=false
open n=44 median=63.9ms p90=74.2ms max=100.4ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=17.4ms
agent show frames=161 dropped=1 longest=27.9ms
idle space worst=0.7ms stalls>16ms=0
idle note worst=0.7ms stalls>16ms=0
type 80665 chars n=80 median=5.7ms p90=10.2ms max=49.8ms
caret start n=30 median=0.2ms p90=0.4ms max=2.3ms
caret end n=30 median=0.2ms p90=0.4ms max=1.0ms
memory start=133MB end=174MB
done
```

## d1 detail split · f9df6dc · 2026-09-29 10:08

```
vault notes=397 picks=44 dim=false
open n=44 median=64.2ms p90=75.9ms max=99.0ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=162 dropped=0 longest=24.1ms
agent show frames=157 dropped=3 longest=33.3ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=5.2ms p90=12.4ms max=60.5ms
caret start n=30 median=0.2ms p90=0.3ms max=14.3ms
caret end n=30 median=0.2ms p90=0.3ms max=1.0ms
focus dim n=12 median=54.6ms p90=59.1ms max=60.7ms
memory start=134MB end=216MB
done
```

## d1 draw-time dim · f9df6dc · 2026-09-29 10:11

```
vault notes=397 picks=44 dim=false
open n=44 median=64.5ms p90=77.5ms max=100.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=19.8ms
agent show frames=159 dropped=1 longest=33.3ms
idle space worst=1.2ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=4.1ms p90=10.4ms max=60.0ms
caret start n=30 median=0.2ms p90=0.3ms max=13.5ms
caret end n=30 median=0.2ms p90=0.4ms max=1.1ms
focus dim n=12 median=22.3ms p90=24.6ms max=25.5ms
memory start=133MB end=183MB
done
```

## d3 state split · 72e458e · 2026-09-29 10:23

```
vault notes=397 picks=44 dim=false
open n=44 median=65.6ms p90=80.7ms max=104.6ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=17.8ms
agent show frames=159 dropped=1 longest=33.3ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.4ms stalls>16ms=0
type 80665 chars n=80 median=5.7ms p90=12.0ms max=59.7ms
caret start n=30 median=0.3ms p90=0.4ms max=1.6ms
caret end n=30 median=0.2ms p90=0.3ms max=1.1ms
focus dim n=12 median=24.0ms p90=26.7ms max=28.3ms
memory start=134MB end=177MB
done
```

## motion 第一版（字数滚动动画，内存问题已在最终版修复）· 92e0fe1 · 2026-09-29 10:47

```
vault notes=397 picks=44 dim=false
open n=44 median=61.1ms p90=72.7ms max=94.0ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=159 dropped=1 longest=28.0ms
agent show frames=157 dropped=2 longest=33.3ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=5.0ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=13.1ms max=54.7ms
caret start n=30 median=0.3ms p90=0.4ms max=1.4ms
caret end n=30 median=0.1ms p90=0.1ms max=0.4ms
focus dim n=12 median=23.4ms p90=25.2ms max=25.9ms
memory start=131MB end=337MB
done
```

## motion (final) · 92e0fe1 · 2026-09-29 11:07

```
vault notes=397 picks=44 dim=false
open n=44 median=62.6ms p90=74.4ms max=89.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=2 longest=25.8ms
agent show frames=156 dropped=1 longest=33.3ms
idle space worst=1.2ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=2.4ms p90=10.8ms max=60.3ms
caret start n=30 median=0.2ms p90=0.4ms max=3.0ms
caret end n=30 median=0.2ms p90=0.4ms max=1.1ms
focus dim n=12 median=24.1ms p90=25.7ms max=26.1ms
memory start=131MB end=151MB
done
```

## motion mode minimal · cbc9195 · 2026-09-29 11:39

```
vault notes=397 picks=44 dim=false
open n=44 median=63.3ms p90=74.4ms max=104.1ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=24.7ms
agent show frames=155 dropped=4 longest=45.2ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=11.5ms max=59.7ms
caret start n=30 median=0.3ms p90=0.5ms max=2.1ms
caret end n=30 median=0.2ms p90=0.3ms max=1.1ms
focus dim n=12 median=24.1ms p90=25.0ms max=26.5ms
memory start=130MB end=150MB
done
```

## motion mode calm · cbc9195 · 2026-09-29 11:40

```
vault notes=397 picks=44 dim=false
open n=44 median=64.2ms p90=75.5ms max=98.6ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=17.0ms
agent show frames=159 dropped=1 longest=33.3ms
idle space worst=1.4ms stalls>16ms=0
idle note worst=1.4ms stalls>16ms=0
type 80665 chars n=80 median=1.1ms p90=11.2ms max=55.7ms
caret start n=30 median=0.2ms p90=0.3ms max=18.4ms
caret end n=30 median=0.2ms p90=0.5ms max=1.3ms
focus dim n=12 median=24.2ms p90=26.8ms max=29.2ms
memory start=130MB end=149MB
done
```

## motion mode lively · cbc9195 · 2026-09-29 11:41

```
vault notes=397 picks=44 dim=false
open n=44 median=66.0ms p90=77.1ms max=98.0ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=161 dropped=0 longest=16.7ms
agent show frames=155 dropped=3 longest=43.3ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=1.1ms p90=10.1ms max=58.3ms
caret start n=30 median=0.3ms p90=0.6ms max=1.6ms
caret end n=30 median=0.2ms p90=0.5ms max=1.4ms
focus dim n=12 median=24.3ms p90=25.4ms max=27.6ms
memory start=130MB end=149MB
done
```

## motion audit (lively) · 5faad7a · 2026-09-29 11:58

```
vault notes=397 picks=44 dim=false
open n=44 median=65.3ms p90=77.6ms max=96.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=20.2ms
agent show frames=159 dropped=1 longest=28.1ms
idle space worst=1.2ms stalls>16ms=0
idle note worst=1.2ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=8.2ms max=60.2ms
caret start n=30 median=0.2ms p90=0.6ms max=2.8ms
caret end n=30 median=0.2ms p90=0.3ms max=1.1ms
focus dim n=12 median=23.0ms p90=24.7ms max=25.1ms
memory start=131MB end=173MB
done
```

## motion audit · minimal · ec8c707 · 2026-09-29 12:14

```
vault notes=397 picks=44 dim=false
open n=44 median=64.8ms p90=76.9ms max=102.4ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=0 longest=24.2ms
agent show frames=156 dropped=3 longest=33.3ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=10.7ms max=59.1ms
caret start n=30 median=0.2ms p90=0.3ms max=16.6ms
caret end n=30 median=0.3ms p90=0.5ms max=1.2ms
focus dim n=12 median=23.4ms p90=24.6ms max=27.8ms
memory start=131MB end=153MB
done
```

## motion audit · calm · ec8c707 · 2026-09-29 12:15

```
vault notes=397 picks=44 dim=false
open n=44 median=61.7ms p90=74.6ms max=98.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=161 dropped=0 longest=24.2ms
agent show frames=156 dropped=4 longest=43.6ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.4ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=8.5ms max=58.7ms
caret start n=30 median=0.3ms p90=0.4ms max=1.2ms
caret end n=30 median=0.2ms p90=0.3ms max=1.0ms
focus dim n=12 median=23.7ms p90=25.7ms max=29.4ms
memory start=131MB end=144MB
done
```

## motion audit · lively · ec8c707 · 2026-09-29 12:16

```
vault notes=397 picks=44 dim=false
open n=44 median=61.9ms p90=74.8ms max=96.9ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=159 dropped=0 longest=24.8ms
agent show frames=154 dropped=4 longest=45.6ms
idle space worst=1.3ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=8.6ms max=65.0ms
caret start n=30 median=0.2ms p90=0.5ms max=2.0ms
caret end n=30 median=0.2ms p90=0.3ms max=1.1ms
focus dim n=12 median=20.3ms p90=24.6ms max=25.0ms
memory start=131MB end=148MB
done
```

## agent panel in its own host · synthetic vault · 2026-09-29

合成库（403 篇，含一篇带 4 张图、公式、表格、callout 的 `heavy.md`），`TWAIN_STRESS_ONLY=agent TWAIN_STRESS_ROUNDS=16 TWAIN_STRESS_GAPS=1`，60 Hz 屏幕。每帧主线程耗时取动画期间（≥5 ms）的中位数。

```
                         开合 16 次（8 开 8 合）                      每帧主线程
before  普通笔记 无会话   hide dropped=1  show dropped=1  longest=33.3ms   10 ms (p90 13)
before  普通笔记 有会话   hide dropped=4  show dropped=3  longest=29.1ms   10 ms (p90 13)
after   普通笔记 无会话   hide dropped=0  show dropped=5  longest=27.3ms   7.5 ms (p90 10)
after   普通笔记 有会话   hide dropped=3  show dropped=0  longest=27.1ms   8 ms (p90 10)
before  heavy.md 无会话   hide dropped=6  show dropped=16 longest=33.3ms   13 ms (p90 16)
before  heavy.md 有会话   hide dropped=9  show dropped=19 longest=33.3ms   14 ms (p90 16)
after   heavy.md 无会话   hide dropped=2  show dropped=1  longest=27.7ms   10 ms (p90 12)
after   heavy.md 有会话   hide dropped=2  show dropped=1  longest=33.3ms   11 ms (p90 12)
```

面板滑动时 AppKit 每帧改一次列宽，窗口的 SwiftUI 布局从头再跑：Agent 栏的两层 `ViewThatFits`、对话记录、输入框每帧都被重新量一遍（`NSHostingView.minSize()` 占面板耗时的大半），虽然面板自身宽度始终不变。`FixedHost` 把面板内容放进自己的 NSHostingView，外层布局不再穿透进去。剩下的每帧开销主要是正文随列宽变化重新居中后整屏重画（图片多的笔记更明显）。

## agent transcript opens at its latest message · synthetic vault · 2026-09-29

对话记录从 `onAppear` 里的 `scrollTo` 改为 `.defaultScrollAnchor(.bottom, for: .initialOffset)`：`onAppear` 执行时 LazyVStack 的行还没量出真实高度，长对话停在顶部（打开面板、切换会话都是如此，ce9d6ee 之前就有）。新写法只在滚动视图第一次布局时起作用，滑动时没有额外的每帧工作。合成库（402 篇），`TWAIN_STRESS_ONLY=agent TWAIN_STRESS_SESSION=1 TWAIN_STRESS_GAPS=1 TWAIN_STRESS_ROUNDS=16`，各跑两次：

```
                  hide                         show                         每帧主线程（≥5 ms）
before  run 1     dropped=1 longest=28.5ms     dropped=0 longest=22.7ms     median 7 ms  p90 9
before  run 2     dropped=3 longest=27.3ms     dropped=1 longest=26.2ms     median 7 ms  p90 9
after   run 1     dropped=4 longest=28.5ms     dropped=1 longest=26.4ms     median 7 ms  p90 9
after   run 2     dropped=3 longest=28.3ms     dropped=0 longest=23.8ms     median 7 ms  p90 9
```

实窗截图验证：`TWAIN_SCENARIO=longreply:<note>`、`longreply:<note>:reopen`（关面板再开）、`longreply:<note>:switch`（切到别的会话再切回），改前三种都停在第一条消息，改后都在最新一条。

## motion inspora 1 · lively (用户设置) · 2282765 · 2026-10-01 23:35

```
vault notes=397 picks=44 dim=false
open n=44 median=55.9ms p90=70.2ms max=93.1ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=1 longest=26.2ms
agent show frames=159 dropped=4 longest=33.3ms
idle space worst=3.6ms stalls>16ms=0
idle note worst=5.3ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=9.6ms max=64.2ms
caret start n=30 median=0.2ms p90=0.3ms max=1.5ms
caret end n=30 median=0.2ms p90=0.4ms max=1.0ms
focus dim n=12 median=22.2ms p90=23.5ms max=24.6ms
memory start=132MB end=147MB
done
```

## motion inspora 2 · lively (用户设置) · 9df3e67 · 2026-10-01 23:45

```
vault notes=397 picks=44 dim=false
open n=44 median=54.8ms p90=65.5ms max=91.5ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=171 dropped=1 longest=33.3ms
agent hide frames=160 dropped=0 longest=23.4ms
agent show frames=161 dropped=2 longest=33.3ms
idle space worst=5.1ms stalls>16ms=0
idle note worst=4.6ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=12.9ms max=58.7ms
caret start n=30 median=0.2ms p90=0.3ms max=2.4ms
caret end n=30 median=0.2ms p90=0.2ms max=0.7ms
focus dim n=12 median=24.3ms p90=28.6ms max=30.6ms
memory start=134MB end=148MB
done
```

## motion inspora 2 · lively · 复测 · 9df3e67 · 2026-10-01 23:46

```
vault notes=397 picks=44 dim=false
open n=44 median=54.8ms p90=66.7ms max=85.4ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=161 dropped=0 longest=23.4ms
agent show frames=159 dropped=2 longest=33.3ms
idle space worst=4.2ms stalls>16ms=0
idle note worst=4.2ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=12.9ms max=52.8ms
caret start n=30 median=0.2ms p90=0.2ms max=0.8ms
caret end n=30 median=0.2ms p90=0.2ms max=0.8ms
focus dim n=12 median=25.7ms p90=28.3ms max=29.5ms
memory start=133MB end=148MB
done
```

## 实验：状态胶囊不滚动 · 9df3e67 · 2026-10-01 23:48

```
vault notes=397 picks=44 dim=false
open n=44 median=56.3ms p90=69.8ms max=92.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=162 dropped=2 longest=28.8ms
agent show frames=158 dropped=2 longest=33.3ms
idle space worst=4.6ms stalls>16ms=0
idle note worst=3.7ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=11.5ms max=58.7ms
caret start n=30 median=0.2ms p90=0.3ms max=2.9ms
caret end n=30 median=0.2ms p90=0.2ms max=0.6ms
focus dim n=12 median=26.6ms p90=32.0ms max=32.2ms
memory start=134MB end=147MB
done
```

## 实验：再关掉目录跟随 · 9df3e67 · 2026-10-01 23:49

```
vault notes=397 picks=44 dim=false
open n=44 median=54.8ms p90=66.3ms max=95.8ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=161 dropped=2 longest=43.2ms
agent show frames=159 dropped=1 longest=33.3ms
idle space worst=3.9ms stalls>16ms=0
idle note worst=4.0ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=10.5ms max=59.7ms
caret start n=30 median=0.2ms p90=0.3ms max=1.1ms
caret end n=30 median=0.2ms p90=0.2ms max=0.9ms
focus dim n=12 median=26.6ms p90=28.8ms max=29.8ms
memory start=133MB end=147MB
done
```

## motion inspora 2 · lively · 目录跟随停稳后计算 · 9df3e67 · 2026-10-01 23:54

```
vault notes=397 picks=44 dim=false
open n=44 median=60.1ms p90=73.2ms max=102.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=3 longest=43.8ms
agent show frames=156 dropped=1 longest=33.3ms
idle space worst=6.6ms stalls>16ms=0
idle note worst=5.3ms stalls>16ms=0
type 80665 chars n=80 median=1.1ms p90=9.9ms max=48.4ms
caret start n=30 median=0.1ms p90=0.2ms max=16.5ms
caret end n=30 median=0.2ms p90=0.2ms max=0.6ms
focus dim n=12 median=28.2ms p90=30.7ms max=32.7ms
memory start=132MB end=152MB
done
```

## motion inspora 3a · lively · agent 岛 + 拷贝确认 · bad5377 · 2026-10-01 23:59

```
vault notes=397 picks=44 dim=false
open n=44 median=59.0ms p90=71.8ms max=96.6ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=171 dropped=1 longest=33.3ms
agent hide frames=163 dropped=0 longest=24.6ms
agent show frames=159 dropped=1 longest=33.3ms
idle space worst=4.4ms stalls>16ms=0
idle note worst=4.4ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=11.4ms max=56.9ms
caret start n=30 median=0.1ms p90=0.3ms max=6.1ms
caret end n=30 median=0.1ms p90=0.2ms max=0.6ms
focus dim n=12 median=26.4ms p90=31.2ms max=31.4ms
memory start=133MB end=148MB
done
```

## motion inspora 3a · 重复1 · bad5377 · 2026-10-02 00:00

```
vault notes=397 picks=44 dim=false
open n=44 median=57.2ms p90=67.3ms max=96.8ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=164 dropped=0 longest=22.6ms
agent show frames=157 dropped=1 longest=33.3ms
idle space worst=5.5ms stalls>16ms=0
idle note worst=4.8ms stalls>16ms=0
type 80665 chars n=80 median=1.0ms p90=9.8ms max=57.2ms
caret start n=30 median=0.2ms p90=0.2ms max=12.3ms
caret end n=30 median=0.2ms p90=0.4ms max=4.6ms
focus dim n=12 median=28.2ms p90=30.7ms max=31.9ms
memory start=133MB end=153MB
done
```

## motion inspora 3a · 重复2 · bad5377 · 2026-10-02 00:01

```
vault notes=397 picks=44 dim=false
open n=44 median=57.6ms p90=70.4ms max=96.1ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=163 dropped=0 longest=16.7ms
agent show frames=158 dropped=3 longest=33.3ms
idle space worst=4.6ms stalls>16ms=0
idle note worst=4.0ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=9.4ms max=57.0ms
caret start n=30 median=0.2ms p90=0.4ms max=6.9ms
caret end n=30 median=0.2ms p90=0.2ms max=0.6ms
focus dim n=12 median=26.5ms p90=31.3ms max=33.4ms
memory start=133MB end=148MB
done
```

## motion inspora 3c · 面板匹配高亮 + 发送键变停止 · eb5d810 · 2026-10-02 00:09

```
vault notes=397 picks=44 dim=false
open n=44 median=60.9ms p90=74.9ms max=98.1ms
sidebar hide frames=171 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=159 dropped=1 longest=33.3ms
agent show frames=159 dropped=1 longest=39.8ms
idle space worst=3.5ms stalls>16ms=0
idle note worst=5.4ms stalls>16ms=0
type 80665 chars n=80 median=0.9ms p90=9.7ms max=60.0ms
caret start n=30 median=0.2ms p90=0.3ms max=8.0ms
caret end n=30 median=0.2ms p90=0.2ms max=0.6ms
focus dim n=12 median=25.8ms p90=32.2ms max=32.7ms
memory start=132MB end=152MB
done
```

## motion inspora 4 · 实色表面，玻璃只留悬浮层 · 442c8ba · 2026-10-02 00:25

```
vault notes=403 picks=44 dim=false
open n=44 median=56.1ms p90=76.8ms max=79.7ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=160 dropped=1 longest=26.0ms
agent show frames=159 dropped=2 longest=33.3ms
idle space worst=5.2ms stalls>16ms=0
idle note worst=3.6ms stalls>16ms=0
type 22785 chars n=80 median=0.6ms p90=1.5ms max=45.1ms
caret start n=30 median=0.6ms p90=4.7ms max=9.0ms
caret end n=30 median=0.5ms p90=1.6ms max=16.5ms
focus dim n=12 median=23.1ms p90=26.5ms max=32.0ms
memory start=147MB end=142MB
done
```

## motion inspora 4b · 常驻动画改走 Core Animation · dd03428 · 2026-10-02 00:39

```
vault notes=403 picks=44 dim=false
open n=44 median=55.2ms p90=77.1ms max=79.6ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=162 dropped=1 longest=26.0ms
agent show frames=161 dropped=0 longest=24.0ms
idle space worst=5.2ms stalls>16ms=0
idle note worst=3.5ms stalls>16ms=0
type 22785 chars n=80 median=0.6ms p90=1.3ms max=39.9ms
caret start n=30 median=0.7ms p90=2.9ms max=16.0ms
caret end n=30 median=0.5ms p90=0.8ms max=12.8ms
focus dim n=12 median=20.1ms p90=24.7ms max=27.2ms
memory start=141MB end=136MB
done
```

## motion inspora 4c · 弹出框改为从触发点长出的面板 · b3c1c68 · 2026-10-02 00:51

```
vault notes=403 picks=44 dim=false
open n=44 median=57.6ms p90=78.7ms max=81.6ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=171 dropped=1 longest=33.3ms
agent hide frames=162 dropped=2 longest=27.6ms
agent show frames=158 dropped=0 longest=17.7ms
idle space worst=3.2ms stalls>16ms=0
idle note worst=4.3ms stalls>16ms=0
type 22785 chars n=80 median=0.5ms p90=1.9ms max=40.1ms
caret start n=30 median=0.7ms p90=6.5ms max=10.8ms
caret end n=30 median=0.4ms p90=0.9ms max=20.0ms
focus dim n=12 median=25.9ms p90=27.1ms max=28.4ms
memory start=138MB end=140MB
done
```

## motion inspora 4f · 页面转场 + 数字滚动 · 6a81b14 · 2026-10-02 01:15

```
vault notes=403 picks=44 dim=false
open n=44 median=57.5ms p90=78.6ms max=80.1ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=171 dropped=1 longest=33.3ms
agent hide frames=160 dropped=0 longest=23.9ms
agent show frames=160 dropped=1 longest=25.5ms
idle space worst=4.5ms stalls>16ms=0
idle note worst=4.8ms stalls>16ms=0
type 22785 chars n=80 median=0.5ms p90=1.6ms max=41.2ms
caret start n=30 median=0.6ms p90=2.9ms max=11.8ms
caret end n=30 median=0.4ms p90=0.9ms max=18.6ms
focus dim n=12 median=24.8ms p90=27.3ms max=27.8ms
memory start=141MB end=139MB
done
```

## recheck sidebar 1 · 6a81b14 · 2026-10-02 01:17

```
vault notes=403 picks=44 dim=false
open n=44 median=58.1ms p90=80.3ms max=83.9ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=162 dropped=2 longest=28.9ms
agent show frames=158 dropped=0 longest=17.6ms
idle space worst=6.0ms stalls>16ms=0
idle note worst=4.3ms stalls>16ms=0
type 22785 chars n=80 median=0.6ms p90=1.5ms max=40.0ms
caret start n=30 median=0.6ms p90=8.4ms max=12.5ms
caret end n=30 median=0.4ms p90=0.5ms max=19.7ms
focus dim n=12 median=20.7ms p90=26.9ms max=27.5ms
memory start=141MB end=142MB
done
```

## recheck sidebar 2 · 6a81b14 · 2026-10-02 01:18

```
vault notes=403 picks=44 dim=false
open n=44 median=61.3ms p90=79.0ms max=82.3ms
sidebar hide frames=172 dropped=0 longest=16.7ms
sidebar show frames=172 dropped=0 longest=16.7ms
agent hide frames=161 dropped=0 longest=23.5ms
agent show frames=159 dropped=2 longest=33.3ms
idle space worst=3.9ms stalls>16ms=0
idle note worst=5.9ms stalls>16ms=0
type 22785 chars n=80 median=0.6ms p90=1.7ms max=32.8ms
caret start n=30 median=0.6ms p90=8.5ms max=12.7ms
caret end n=30 median=0.5ms p90=1.0ms max=17.8ms
focus dim n=12 median=25.2ms p90=27.2ms max=28.2ms
memory start=140MB end=139MB
done
```

## motion inspora 4g · 侧栏树线 · e48adf9 · 2026-10-02 01:23

```
vault notes=403 picks=44 dim=false
open n=44 median=52.6ms p90=74.7ms max=78.6ms
sidebar hide frames=0 dropped=0 longest=0.0ms
sidebar show frames=0 dropped=0 longest=0.0ms
agent hide frames=0 dropped=0 longest=0.0ms
agent show frames=0 dropped=0 longest=0.0ms
idle space worst=1.2ms stalls>16ms=0
idle note worst=1.3ms stalls>16ms=0
type 22785 chars n=80 median=0.5ms p90=1.4ms max=36.6ms
caret start n=30 median=0.7ms p90=2.1ms max=12.7ms
caret end n=30 median=0.7ms p90=9.6ms max=16.5ms
focus dim n=12 median=18.7ms p90=24.5ms max=27.1ms
memory start=141MB end=152MB
done
```

## motion inspora 4g · 侧栏树线（显示器唤醒后重测） · e48adf9 · 2026-10-02 01:24

```
vault notes=403 picks=44 dim=false
open n=44 median=56.2ms p90=78.3ms max=80.2ms
sidebar hide frames=170 dropped=0 longest=16.7ms
sidebar show frames=171 dropped=1 longest=33.3ms
agent hide frames=159 dropped=2 longest=27.1ms
agent show frames=137 dropped=1 longest=25.7ms
idle space worst=4.4ms stalls>16ms=0
idle note worst=5.3ms stalls>16ms=0
type 22785 chars n=80 median=0.6ms p90=1.6ms max=23.9ms
caret start n=30 median=0.7ms p90=4.5ms max=23.0ms
caret end n=30 median=0.7ms p90=3.0ms max=13.6ms
focus dim n=12 median=9.2ms p90=21.9ms max=23.4ms
memory start=141MB end=143MB
done
```

## motion inspora 4p · 页面容器改 ZStack，标题/工具栏只挂一次 · c004c2a · 2026-10-02 03:48

```
vault notes=403 picks=44 dim=false
open n=44 median=54.4ms p90=77.4ms max=79.5ms
sidebar hide frames=0 dropped=0 longest=0.0ms
sidebar show frames=0 dropped=0 longest=0.0ms
agent hide frames=0 dropped=0 longest=0.0ms
agent show frames=0 dropped=0 longest=0.0ms
idle space worst=6.0ms stalls>16ms=0
idle note worst=4.2ms stalls>16ms=0
type 22785 chars n=80 median=0.6ms p90=2.5ms max=25.5ms
caret start n=30 median=0.8ms p90=4.4ms max=24.9ms
caret end n=30 median=0.7ms p90=3.3ms max=20.9ms
focus dim n=12 median=17.3ms p90=22.9ms max=25.2ms
memory start=140MB end=159MB
done
```

## motion inspora 4p · 重测（显示器唤醒） · c004c2a · 2026-10-02 03:49

```
vault notes=403 picks=44 dim=false
open n=44 median=56.3ms p90=77.8ms max=80.7ms
sidebar hide frames=171 dropped=0 longest=16.7ms
sidebar show frames=173 dropped=0 longest=16.7ms
agent hide frames=78 dropped=2 longest=33.3ms
agent show frames=81 dropped=0 longest=19.1ms
idle space worst=3.2ms stalls>16ms=0
idle note worst=3.9ms stalls>16ms=0
type 22785 chars n=80 median=0.5ms p90=1.6ms max=40.0ms
caret start n=30 median=0.8ms p90=4.9ms max=12.0ms
caret end n=30 median=0.6ms p90=3.3ms max=14.4ms
focus dim n=12 median=19.0ms p90=22.4ms max=23.5ms
memory start=142MB end=163MB
done
```

## 对照 · 4o 与 4p 同一时段各跑一次（显示器保持唤醒）· 2026-10-02

```
4o  open median=53.3ms p90=76.8ms  sidebar 0/0 dropped  agent 2/2 dropped  memory 142→165MB
4p  open median=55.2ms p90=77.3ms  sidebar 0/1 dropped  agent 2/1 dropped  memory 140→138MB
```

压测后内存同一版本两次之间能差 20 MB 以上，单次的内存数字不能当作回归依据；帧数为 0 的记录是显示器睡着时测的，作废。
