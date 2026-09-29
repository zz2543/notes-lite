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
