// PROTOTYPE 助手形象: one set of particles that is either a round solid body with a face (idle, done,
// wait, error) or a turning dotted sphere (think, search, read, write, run). States morph, never swap.
import React from "react";

export const FIGURE_STATES = [
  ["idle", "待命"], ["think", "思考"], ["search", "搜索"], ["read", "读取"], ["write", "写入"],
  ["run", "运行命令"], ["done", "完成"], ["wait", "等你回应"], ["error", "出错"],
];
const SOLID = new Set(["idle", "done", "wait", "error"]);

const N = 150;
const sphere = Array.from({ length: N }, (_, i) => {
  const y = 1 - (i / (N - 1)) * 2;
  const r = Math.sqrt(1 - y * y);
  const th = i * 2.399963;
  return [Math.cos(th) * r, y, Math.sin(th) * r];
});
// Where each particle settles inside the body: a sunflower disc, outer ones near the rim.
const disc = Array.from({ length: N }, (_, i) => {
  const r = Math.sqrt((i + 0.5) / N) * 0.92;
  const th = i * 2.399963;
  return [Math.cos(th) * r, Math.sin(th) * r];
});
const delay = Array.from({ length: N }, (_, i) => ((i * 0.618034) % 1) * 0.45);

// Face targets per state; every number is eased toward each frame, so expressions blend.
const faces = {
  idle: { smile: 0.25, open: 0, crescent: 0, eye: 1, hue: 0, tilt: 0 },
  done: { smile: 0.8, open: 0, crescent: 1, eye: 1, hue: 0, tilt: 0 },
  wait: { smile: 0, open: 1, crescent: 0, eye: 1.18, hue: 0, tilt: 0 },
  error: { smile: -0.5, open: 0, crescent: 0, eye: 0.85, hue: 1, tilt: 1 },
};

function heat(state, p, t) {
  const [x, y, z] = p;
  const w = (k) => t * k;
  switch (state) {
    case "think": return Math.pow(Math.max(0, Math.sin(x * 3 + y * 4 + w(1.6))), 3);
    case "search": return Math.pow(Math.max(0, Math.sin(x * 5 - w(2.6))), 4);
    case "read": return Math.max(0, 1 - Math.abs(y - Math.sin(w(1.4)) * 0.9) * 4);
    case "write": return Math.pow(Math.max(0, Math.sin(Math.atan2(z, x) * 2 - w(2.8))), 4);
    case "run": return Math.pow(Math.max(0, Math.sin(y * 6 + w(4))), 6);
    default: return 0;
  }
}

function hexToRgb(h) {
  const n = parseInt(h.replace("#", ""), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
const mix = (a, b, f) => a.map((v, i) => Math.round(v + (b[i] - v) * f));
const smooth = (x) => { const c = Math.min(1, Math.max(0, x)); return c * c * (3 - 2 * c); };

export function Figure({ state = "idle", size = 40, tint = "#0a84ff", ink = "#8a8a93", fill = "#1d1d1f", feature = "#ffffff", reduced = false, detail = "full" }) {
  const ref = React.useRef(null);
  const live = React.useRef({ state, tint, ink, fill, feature, reduced, detail });
  live.current = { state, tint, ink, fill, feature, reduced, detail };

  React.useEffect(() => {
    const cv = ref.current;
    const ctx = cv.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    cv.width = size * dpr; cv.height = size * dpr;
    let raf = 0, last = performance.now(), t = 0;
    // Springs: solid 0 = sphere, 1 = body. Squash gives the "done" bounce and the error shake.
    let solid = SOLID.has(state) ? 1 : 0, vSolid = 0, squash = 0, vSquash = 0, shake = 0;
    const face = { ...faces[SOLID.has(state) ? state : "idle"] };
    let gaze = [0, 0], blink = 0, nextBlink = 2 + Math.random() * 3, prev = state;
    let mouse = [0, 0];
    const onMove = (e) => {
      const r = cv.getBoundingClientRect();
      mouse = [(e.clientX - (r.left + r.width / 2)) / 400, (e.clientY - (r.top + r.height / 2)) / 400];
    };
    window.addEventListener("pointermove", onMove);

    const frame = (now) => {
      const L = live.current;
      const dt = Math.min(0.05, (now - last) / 1000); last = now;
      if (!L.reduced) t += dt;
      if (L.state !== prev) {
        if (L.state === "done") vSquash += 9;
        if (L.state === "error") shake = 1;
        prev = L.state;
      }
      const target = SOLID.has(L.state) ? 1 : 0;
      if (L.reduced) { solid = target; vSolid = 0; }
      // Critically damped, so the fusion glides in without overshooting.
      else { vSolid += ((target - solid) * 26 - vSolid * 10.2) * dt; solid = Math.min(1, Math.max(0, solid + vSolid * dt)); }
      vSquash += (-squash * 160 - vSquash * 9) * dt; squash += vSquash * dt;
      shake = Math.max(0, shake - dt * 2.2);
      const ft = faces[SOLID.has(L.state) ? L.state : "idle"];
      const k = L.reduced ? 1 : Math.min(1, dt * 10);
      for (const key in face) face[key] += (ft[key] - face[key]) * k;
      if (!L.reduced) {
        nextBlink -= dt;
        if (nextBlink < 0) { blink = 1; nextBlink = 2.5 + Math.random() * 3.5; }
        blink = Math.max(0, blink - dt * 7);
      }
      const look = L.state === "idle" ? mouse.map((v) => Math.max(-1, Math.min(1, v))) : [0, 0];
      gaze = gaze.map((g, i) => g + (look[i] - g) * Math.min(1, dt * 6));

      draw(ctx, L, size * dpr, { solid, squash, shake, face, gaze, blink, t });
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => { cancelAnimationFrame(raf); window.removeEventListener("pointermove", onMove); };
  }, [size]);

  return <canvas ref={ref} style={{ width: size, height: size, display: "block" }} aria-label="助手形象" />;
}

function draw(ctx, L, px, s) {
  const { solid, squash, shake, face, gaze, blink, t } = s;
  ctx.clearRect(0, 0, px, px);
  const c = px / 2;
  const R = px * (L.detail !== "full" ? 0.4 : 0.36);
  const accent = hexToRgb(L.tint);
  const red = [255, 69, 58];
  // Flat and monochrome: the body is the ink of the theme, the face is cut out of it.
  const body = mix(hexToRgb(L.fill), red, face.hue);
  const feat = `rgb(${mix(hexToRgb(L.feature), [255, 255, 255], face.hue).join(",")})`;
  const inkC = hexToRgb(L.ink);
  const small = L.detail !== "full";
  const sx = Math.sin(t * 40) * shake * px * 0.03;
  const breathe = 1 + Math.sin(t * 1.6) * 0.015;
  const scaleX = (1 + squash * 0.05) * breathe, scaleY = (1 - squash * 0.05) * breathe;
  // The body grows from the centre while the particles fall inward; where they meet, they merge.
  const grow = smooth((solid - 0.05) / 0.95);
  const rb = R * grow;

  // Orbiting motes: the particle signature that stays even when solid.
  if (!small) {
    for (let i = 0; i < 5; i++) {
      const a = t * (0.5 + i * 0.13) + i * 1.3;
      const rr = R * (1.32 + 0.06 * Math.sin(t + i));
      const x = c + Math.cos(a) * rr, y = c + Math.sin(a) * rr * 0.55;
      ctx.fillStyle = `rgba(${body.join(",")},${(0.2 + 0.2 * Math.sin(a * 2 + i) ** 2) * (0.4 + 0.6 * solid)})`;
      ctx.beginPath(); ctx.arc(x + sx, y, px * 0.011, 0, Math.PI * 2); ctx.fill();
    }
  }

  // The body: a flat disc. Incoming particles take its colour and melt into its edge.
  if (rb > 0.5) {
    ctx.save();
    ctx.translate(c + sx, c);
    ctx.scale(scaleX, scaleY * (1 + face.open * 0.03));
    ctx.fillStyle = `rgb(${body.join(",")})`;
    ctx.beginPath(); ctx.arc(0, 0, rb, 0, Math.PI * 2); ctx.fill();

    // Face: rounded-square eyes carry the expression; a short thin mouth sits under them.
    const fa = smooth((solid - 0.72) / 0.28);
    if (fa > 0.01) {
      ctx.globalAlpha = fa;
      ctx.fillStyle = feat;
      ctx.strokeStyle = feat;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      const k = small ? 1.2 : 1;
      const ew = R * 0.2 * k * face.eye, eh = R * 0.27 * k * face.eye;
      const ex = R * 0.3, ey = -R * 0.08;
      const gx = gaze[0] * R * 0.12, gy = gaze[1] * R * 0.08;
      for (const side of [-1, 1]) {
        const x = side * ex + gx, y = ey + gy;
        const h = eh * Math.max(0.1, 1 - blink) * (1 - face.crescent * 0.95);
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(side * -0.32 * face.tilt);
        if (h > 0.5) {
          ctx.beginPath();
          ctx.roundRect(-ew / 2, -h / 2, ew, h, Math.min(ew, h) * 0.38);
          ctx.fill();
        }
        if (face.crescent > 0.05) {
          // Happy: the eyes fold into ^ ^.
          ctx.globalAlpha = fa * face.crescent;
          ctx.lineWidth = ew * 0.42;
          ctx.beginPath();
          ctx.moveTo(-ew * 0.6, eh * 0.12);
          ctx.lineTo(0, -eh * 0.28);
          ctx.lineTo(ew * 0.6, eh * 0.12);
          ctx.stroke();
          ctx.globalAlpha = fa;
        }
        ctx.restore();
      }
      const my = R * 0.32 + gy * 0.5, mw = R * (small ? 0.2 : 0.15);
      ctx.lineWidth = R * (small ? 0.08 : 0.06);
      if (face.open > 0.05) {
        ctx.globalAlpha = fa * face.open;
        ctx.beginPath(); ctx.roundRect(gx * 0.5 - R * 0.07, my - R * 0.06 * face.open, R * 0.14, R * 0.13 * face.open, R * 0.05); ctx.fill();
        ctx.globalAlpha = fa;
      }
      if (face.open < 0.95 && !small) {
        ctx.globalAlpha = fa * (1 - face.open);
        ctx.beginPath();
        ctx.moveTo(gx * 0.5 - mw, my - face.smile * R * 0.03);
        ctx.quadraticCurveTo(gx * 0.5, my + face.smile * R * 0.14, gx * 0.5 + mw, my - face.smile * R * 0.03);
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    }
    ctx.restore();
  }

  // Particles: on the sphere when working; while the body forms they drift inward on a gentle
  // curve and dissolve as the growing body reaches them (and emerge from its edge on the way out).
  const rot = t * 0.9, tilt = 0.35, ct = Math.cos(tilt), st = Math.sin(tilt), ca = Math.cos(rot), sa = Math.sin(rot);
  const sphereR = R * 1.12;
  for (let i = 0; i < N; i++) {
    const p = sphere[i];
    const x1 = p[0] * ca + p[2] * sa, z1 = -p[0] * sa + p[2] * ca;
    const y1 = p[1] * ct - z1 * st, z2 = p[1] * st + z1 * ct;
    const depth = (z2 + 1) / 2;
    const pi = smooth((solid - delay[i] * 0.6) / (1 - 0.27));
    const swirl = Math.sin(pi * Math.PI) * R * 0.08;
    const ang = Math.atan2(y1, x1) + Math.PI / 2;
    const ax = x1 * sphereR, ay = y1 * sphereR;
    const bx = disc[i][0] * R * 0.85, by = disc[i][1] * R * 0.85;
    const dx = ax + (bx - ax) * pi + Math.cos(ang) * swirl;
    const dy = ay + (by - ay) * pi + Math.sin(ang) * swirl;
    const d = Math.hypot(dx, dy);
    const absorbed = rb > 0.5 ? smooth((rb - d) / (R * 0.18) + 0.5) : 0;
    const h = heat(L.state, p, t) * (1 - pi);
    const col = L.state === "error" ? red : mix(mix(inkC, accent, Math.min(1, h * 1.3)), body, pi);
    const alpha = (0.2 + depth * 0.8) * (1 - absorbed);
    if (alpha < 0.02) continue;
    const dot = (0.35 + depth * 0.6) * px / 40 * (1 + pi * 0.3);
    ctx.fillStyle = `rgba(${col.join(",")},${alpha})`;
    ctx.beginPath(); ctx.arc(c + dx + sx, c + dy, dot, 0, Math.PI * 2); ctx.fill();
  }

  // Waiting: a thin ring breathes around it.
  if (L.state === "wait" && !small) {
    const k = (Math.sin(t * 3) + 1) / 2;
    ctx.strokeStyle = `rgba(${accent.join(",")},${0.25 + k * 0.45})`;
    ctx.lineWidth = px * 0.014;
    ctx.beginPath(); ctx.arc(c, c, R * (1.25 + k * 0.08), 0, Math.PI * 2); ctx.stroke();
  }
}
