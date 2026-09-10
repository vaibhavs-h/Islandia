"use client";

import { useRef, useState } from "react";
import { AirPodsMaxIcon, AirPodsProIcon } from "@/components/site/AirPodsIcons";
import Reveal from "@/components/site/Reveal";

const RING_RADIUS = 8;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;
const REST_FRACTION = 0.7395;

const NUM_LO = 10;
const NUM_HI = 82;
const NUM_DURATION = 950;

function cubicBezierEase(x1: number, y1: number, x2: number, y2: number) {
  function bezier(t: number, a: number, b: number) {
    const it = 1 - t;
    return 3 * it * it * t * a + 3 * it * t * t * b + t * t * t;
  }
  return (x: number) => {
    let lo = 0;
    let hi = 1;
    let t = x;
    for (let i = 0; i < 20; i++) {
      t = (lo + hi) / 2;
      if (bezier(t, x1, x2) < x) lo = t;
      else hi = t;
    }
    return bezier(t, y1, y2);
  };
}

const ease = cubicBezierEase(0.22, 0.61, 0.2, 1);

export default function LiveAirPodsCard({
  className,
  baseDelay = 0,
}: {
  className?: string;
  baseDelay?: number;
}) {
  const [num, setNum] = useState(NUM_LO);
  const frameRef = useRef<number | null>(null);
  const numRef = useRef(NUM_LO);

  function animateTo(target: number) {
    if (frameRef.current) cancelAnimationFrame(frameRef.current);
    const start = performance.now();
    const from = numRef.current;
    function tick(now: number) {
      const t = Math.min(1, (now - start) / NUM_DURATION);
      const value = Math.round(from + (target - from) * ease(t));
      numRef.current = value;
      setNum(value);
      if (t < 1) frameRef.current = requestAnimationFrame(tick);
    }
    frameRef.current = requestAnimationFrame(tick);
  }

  return (
    <div
      className={`group flex h-full flex-col gap-8 rounded-3xl bg-background-soft p-7 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)] ${className ?? ""}`}
      onMouseEnter={() => animateTo(NUM_HI)}
      onMouseLeave={() => animateTo(NUM_LO)}
    >
      <div className="flex flex-col gap-3">
        <Reveal delay={baseDelay}>
          <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
            Every pair, <span className="italic">always visible.</span>
          </h3>
        </Reveal>
        <Reveal delay={baseDelay + 0.1}>
          <p className="text-sm leading-relaxed text-foreground-muted">
            Battery and volume, the moment they connect.
          </p>
        </Reveal>
      </div>

      <Reveal delay={baseDelay + 0.2} className="mt-auto flex flex-col gap-3">
        <div className="flex items-center justify-between rounded-full bg-black px-5 py-3.5 text-white transition-transform duration-[550ms] ease-[cubic-bezier(.22,.61,.2,1)] group-hover:-translate-x-1.5 group-hover:scale-[1.03]">
          <div className="flex items-center gap-3">
            <AirPodsProIcon className="h-6 w-6 text-white" />
            <span className="text-sm font-medium">AirPods Pro</span>
          </div>
          <svg width="20" height="20" viewBox="0 0 20 20" className="-rotate-90">
            <circle
              cx="10"
              cy="10"
              r={RING_RADIUS}
              fill="none"
              stroke="rgba(255,255,255,0.2)"
              strokeWidth="2.5"
            />
            <circle
              cx="10"
              cy="10"
              r={RING_RADIUS}
              fill="none"
              stroke="#34d399"
              strokeWidth="2.5"
              strokeDasharray={RING_CIRCUMFERENCE}
              strokeDashoffset={RING_CIRCUMFERENCE * (1 - REST_FRACTION)}
              strokeLinecap="round"
              className="[filter:drop-shadow(0_0_5px_rgba(52,199,89,0.55))] transition-[stroke-dashoffset] duration-[1100ms] ease-[cubic-bezier(.22,.61,.2,1)] group-hover:[stroke-dashoffset:2.91px]"
            />
          </svg>
        </div>

        <div className="flex items-center justify-between rounded-full bg-black px-5 py-3.5 text-white transition-transform duration-[550ms] ease-[cubic-bezier(.22,.61,.2,1)] group-hover:translate-x-1.5 group-hover:scale-[1.03]">
          <div className="flex items-center gap-3">
            <AirPodsMaxIcon className="h-6 w-6 text-white" />
            <span className="text-sm font-medium">AirPods Max</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="relative h-[7px] w-14 overflow-hidden rounded-full bg-white/[0.13]">
              <span className="absolute inset-y-0 left-0 w-[10%] rounded-full bg-[rgb(224,72,62)] transition-[width,background-color] duration-[950ms] ease-[cubic-bezier(.22,.61,.2,1)] group-hover:w-[82%] group-hover:bg-[rgb(52,199,89)]" />
            </div>
            <span className="w-6 text-right text-xs text-white/70">{num}</span>
          </div>
        </div>
      </Reveal>
    </div>
  );
}
