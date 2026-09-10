"use client";

import { useEffect, useState } from "react";
import { DynamicIsland } from "@/components/ui/dynamic-island";
import Reveal from "@/components/site/Reveal";

const CYCLE_VIEWS = ["ring", "timer", "notification"] as const;
const CYCLE_MS = 2000;

export default function DynamicIslandFeatureCard({
  className,
  baseDelay = 0,
}: {
  className?: string;
  baseDelay?: number;
}) {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const id = setInterval(() => {
      setIndex((i) => (i + 1) % CYCLE_VIEWS.length);
    }, CYCLE_MS);
    return () => clearInterval(id);
  }, []);

  return (
    <div
      className={`group flex h-full flex-col items-center justify-between gap-8 rounded-3xl bg-background-soft p-6 text-center transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)] ${className ?? ""}`}
    >
      <Reveal delay={baseDelay}>
        <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
          Calls, timers, <span className="italic">alerts.</span>
        </h3>
      </Reveal>
      <Reveal delay={baseDelay + 0.1} className="flex items-center justify-center overflow-hidden">
        <DynamicIsland
          view={CYCLE_VIEWS[index]}
          showNav={false}
          className="pointer-events-none flex origin-center scale-[0.92] items-center justify-center"
        />
      </Reveal>
    </div>
  );
}
