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
