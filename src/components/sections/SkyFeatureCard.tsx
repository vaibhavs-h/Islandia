"use client";

import { useState } from "react";
import SkyToggle from "@/components/ui/sky-toggle";
import Reveal from "@/components/site/Reveal";

export default function SkyFeatureCard({
  className,
  baseDelay = 0,
}: {
  className?: string;
  baseDelay?: number;
}) {
  const [night, setNight] = useState(false);

  return (
    <div
      className={`group flex h-full flex-col items-center justify-between gap-8 rounded-3xl p-6 text-center transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)] ${
        night
          ? "bg-foreground text-background hover:bg-background-soft hover:text-foreground"
          : "bg-background-soft text-foreground hover:bg-foreground hover:text-background"
      } ${className ?? ""}`}
    >
      <Reveal delay={baseDelay}>
        <h3 className="font-display text-lg font-semibold tracking-tight">
          Looks right, <span className="italic">day or night.</span>
        </h3>
      </Reveal>
      <Reveal delay={baseDelay + 0.1} className="flex justify-center">
        <SkyToggle night={night} onToggle={() => setNight((v) => !v)} />
      </Reveal>
    </div>
  );
}
