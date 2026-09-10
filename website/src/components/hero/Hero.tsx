"use client";

import { useMotionValueEvent, useScroll } from "framer-motion";
import { useEffect, useRef } from "react";
import AppleMark from "@/components/site/AppleMark";
import SectionCard from "@/components/site/SectionCard";
import LaurelBranch from "./LaurelBranch";

const VIDEO_DURATION = 11.2;

function lerpClamp(
  value: number,
  inMin: number,
  inMax: number,
  outMin: number,
  outMax: number,
) {
  const t = Math.min(1, Math.max(0, (value - inMin) / (inMax - inMin)));
  return outMin + t * (outMax - outMin);
}

function easeInOutCubic(t: number) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

// Native `scrollTo({ behavior: "smooth" })` durations vary with distance in a
// way that reads as an abrupt jump for a snap this size - animating it
// ourselves keeps the duration (and easing) fixed regardless of distance.
function smoothScrollTo(target: number, duration = 650) {
  const start = window.scrollY;
  const distance = target - start;
  const startTime = performance.now();

  function step(now: number) {
    const t = Math.min(1, (now - startTime) / duration);
    window.scrollTo(0, start + distance * easeInOutCubic(t));
    if (t < 1) requestAnimationFrame(step);
  }

  requestAnimationFrame(step);
}

type ChapterWindow = { in0: number; in1: number; out0: number; out1: number };

function applyChapter(
  el: HTMLElement | null,
  progress: number,
  window: ChapterWindow,
) {
  if (!el) return;
  const opacity =
    progress < window.out0
      ? lerpClamp(progress, window.in0, window.in1, 0, 1)
      : lerpClamp(progress, window.out0, window.out1, 1, 0);
  el.style.opacity = String(opacity);
  el.style.transform = `translateY(${lerpClamp(opacity, 0, 1, 14, 0)}px)`;
}

const CHAPTERS: Record<string, ChapterWindow> = {
  // in0/in1 sit at or below 0 so the intro is already fully visible at
  // progress 0 - both on first paint and whenever scroll returns to the top.
  intro: { in0: -0.01, in1: 0, out0: 0.05, out1: 0.14 },
  chapter2: { in0: 0.32, in1: 0.39, out0: 0.52, out1: 0.58 },
  // out0/out1 sit at/above 1 (unreachable) so these hold at full opacity
  // once in - this is the last beat of the hero, it stays instead of fading.
  ctaHeading: { in0: 0.76, in1: 0.79, out0: 1, out1: 1.01 },
  ctaSub: { in0: 0.785, in1: 0.81, out0: 1, out1: 1.01 },
  ctaButtons: { in0: 0.8, in1: 0.83, out0: 1, out1: 1.01 },
};

export default function Hero() {
  const containerRef = useRef<HTMLDivElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);

  const introRef = useRef<HTMLDivElement>(null);
  const chapter2Ref = useRef<HTMLDivElement>(null);
  const ctaHeadingRef = useRef<HTMLDivElement>(null);
  const ctaSubRef = useRef<HTMLParagraphElement>(null);
  const ctaButtonsRef = useRef<HTMLDivElement>(null);
  const ctaLaurelLeftRef = useRef<HTMLSpanElement>(null);
  const ctaLaurelRightRef = useRef<HTMLSpanElement>(null);
  const scrollHintRef = useRef<HTMLDivElement>(null);

  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ["start start", "end end"],
  });

  // Written via refs, not useTransform+motion.div style: that path silently
  // desyncs (stale/non-monotonic opacity) with framer-motion 13.2.0 on
  // React 19.2/Next 16 Turbopack. Plain DOM writes off the same scroll
  // value sidestep it.
  function syncToProgress(latest: number) {
    if (videoRef.current && videoRef.current.readyState >= 1) {
      videoRef.current.currentTime = latest * VIDEO_DURATION;
    }

    applyChapter(introRef.current, latest, CHAPTERS.intro);
    applyChapter(chapter2Ref.current, latest, CHAPTERS.chapter2);
    applyChapter(ctaHeadingRef.current, latest, CHAPTERS.ctaHeading);
    applyChapter(ctaSubRef.current, latest, CHAPTERS.ctaSub);
    applyChapter(ctaButtonsRef.current, latest, CHAPTERS.ctaButtons);
    applyChapter(ctaLaurelLeftRef.current, latest, CHAPTERS.ctaButtons);
    applyChapter(ctaLaurelRightRef.current, latest, CHAPTERS.ctaButtons);

    if (scrollHintRef.current) {
      scrollHintRef.current.style.opacity = String(
        lerpClamp(latest, 0, 0.06, 1, 0),
      );
    }
  }

  useMotionValueEvent(scrollYProgress, "change", syncToProgress);

  // useMotionValueEvent's "change" callback only fires on an actual change,
  // so it never runs for the initial value on mount - without this, every
  // element sits at its unstyled CSS default (visible) until the first
  // scroll tick, which is exactly the load-time flash this was fixing.
  useEffect(() => {
    videoRef.current?.pause();
    syncToProgress(scrollYProgress.get());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Once scroll passes the container's pinned range (progress reaches 1),
  // the sticky video releases and slides away over the final viewport's
  // worth of scroll while the next section slides up underneath it - if the
  // user stops mid-release, that split view reads as a layout glitch. Snap
  // to whichever end is closer once scrolling settles there.
  useEffect(() => {
    let settleTimer: ReturnType<typeof setTimeout> | undefined;

    function snapIfStraddling() {
      const container = containerRef.current;
      if (!container) return;

      const viewportHeight = window.innerHeight;
      const pinEnd = container.offsetTop + container.offsetHeight - viewportHeight;
      const releaseEnd = container.offsetTop + container.offsetHeight;
      const midpoint = pinEnd + viewportHeight / 2;
      const epsilon = 2;

      const scrollY = window.scrollY;
      if (scrollY <= pinEnd + epsilon || scrollY >= releaseEnd - epsilon) return;

      smoothScrollTo(scrollY < midpoint ? pinEnd : releaseEnd);
    }

    function onScroll() {
      if (settleTimer) clearTimeout(settleTimer);
      settleTimer = setTimeout(snapIfStraddling, 150);
    }

    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (settleTimer) clearTimeout(settleTimer);
    };
  }, []);

  return (
    <div id="hero" ref={containerRef} className="relative h-[320vh]">
      <div className="sticky top-0 h-screen w-full overflow-hidden bg-black">
        <video
          ref={videoRef}
          className="absolute inset-0 h-full w-full object-cover"
          src="/video/hero.mp4"
          poster="/video/hero-poster.jpg"
          muted
          playsInline
          preload="auto"
        />
        <div className="absolute inset-0 bg-black/15" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-[55%] bg-gradient-to-t from-background/55 via-background/20 to-transparent" />

        <div
          ref={introRef}
          className="pointer-events-none relative z-10 flex h-full flex-col px-6 py-6 sm:px-10 sm:py-8"
        >
          <div className="flex items-start justify-between font-mono text-xs font-bold uppercase tracking-[0.25em] text-foreground/70">
            <span>The Dynamic Island</span>
            <span>{new Date().getFullYear()}</span>
          </div>

          <div className="flex h-[50vh] flex-col items-center justify-center text-center">
            <span
              className="animate-hero-enter mb-4 flex items-center gap-2 font-mono text-[0.9375rem] font-bold uppercase tracking-[0.25em] text-foreground/70"
              style={{ animationDelay: "150ms" }}
            >
              <AppleMark className="h-[0.9375rem] w-[0.9375rem]" />
              For macOS
            </span>
            <h1
              className="animate-hero-enter font-display text-[clamp(4.375rem,16.25vw,11.875rem)] font-black leading-[0.9] tracking-tight text-foreground"
              style={{ animationDelay: "300ms" }}
            >
              Islandia
            </h1>
          </div>
        </div>

        <div
          ref={chapter2Ref}
          style={{ opacity: 0 }}
          className="pointer-events-none absolute inset-x-0 top-0 w-full"
        >
          <div className="flex justify-center px-6 pt-5 sm:pt-7">
            <SectionCard
              className="max-w-4xl bg-black px-10 py-6 sm:px-16 sm:py-8"
              dotClassName="fill-white/20"
            >
              <div className="flex flex-col items-start">
                <p className="text-xs text-[crimson] md:text-md lg:text-lg xl:text-2xl">
                  I believe
                </p>
                <div className="font-display text-lg tracking-tighter text-white md:text-4xl lg:text-[3.375rem] xl:text-7xl">
                  <div className="flex gap-1 md:gap-2 lg:gap-3 xl:gap-4">
                    <span className="font-semibold">&quot;Design should be</span>
                    <span className="font-thin">easy to</span>
                  </div>
                  <div className="flex gap-1 md:gap-2 lg:gap-3 xl:gap-4">
                    <span className="font-thin">understand</span>
                    <span className="font-semibold">because</span>
                    <span className="font-thin">simple</span>
                  </div>
                  <div className="flex gap-1 md:gap-2 lg:gap-3 xl:gap-4">
                    <span className="font-thin">ideas</span>
                    <span className="font-semibold">are quicker to</span>
                  </div>
                  <span className="font-semibold">grasp...&quot;</span>
                </div>
              </div>
            </SectionCard>
          </div>
        </div>

        <div className="pointer-events-none absolute inset-x-0 top-0 flex h-[50vh] items-center justify-center px-6">
          <div className="pointer-events-auto flex flex-col items-center text-center">
            <div className="relative flex justify-center">
              <span
                ref={ctaLaurelLeftRef}
                style={{ opacity: 0 }}
                className="absolute top-1/2 right-full mr-3 -translate-y-1/2 sm:mr-6"
              >
                <LaurelBranch className="hidden h-[17.5rem] w-[5.46875rem] text-black sm:block md:h-[19.6875rem] md:w-[6.015625rem]" />
              </span>
              <h2
                ref={ctaHeadingRef}
                style={{ opacity: 0 }}
                className="font-display text-[5.4rem] leading-[0.9] font-bold tracking-tight text-foreground sm:text-[6.75rem]"
              >
                Wide <span className="font-black italic">awake.</span>
              </h2>
              <span
                ref={ctaLaurelRightRef}
                style={{ opacity: 0 }}
                className="absolute top-1/2 left-full ml-3 -translate-y-1/2 sm:ml-6"
              >
                <LaurelBranch
                  flip
                  className="hidden h-[17.5rem] w-[5.46875rem] text-black sm:block md:h-[19.6875rem] md:w-[6.015625rem]"
                />
              </span>
            </div>
            <p
              ref={ctaSubRef}
              style={{ opacity: 0 }}
              className="mt-[1.7rem] text-lg text-foreground-muted"
            >
              The Dynamic Island, on your Mac.
            </p>
            <div
              ref={ctaButtonsRef}
              style={{ opacity: 0 }}
              className="mt-4 flex w-full items-center justify-center gap-4"
            >
              <a
                href="#pricing"
                className="flex items-center gap-2.5 rounded-full bg-foreground px-6.25 py-2.5 text-[1.09375rem] font-medium text-background transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:scale-[1.03] hover:opacity-85 active:scale-95"
              >
                <AppleMark className="h-5 w-5" />
                Download for Mac
              </a>
              <a
                href="#features"
                className="text-[1.09375rem] font-medium text-foreground underline underline-offset-4 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:opacity-70 active:scale-95"
              >
                Purchase
              </a>
            </div>
          </div>
        </div>

        <div
          ref={scrollHintRef}
          className="pointer-events-none absolute inset-x-0 bottom-8 flex justify-center text-xs font-bold uppercase tracking-[0.2em] text-foreground/60"
        >
          <span>Scroll</span>
        </div>
      </div>
    </div>
  );
}
