import Reveal from "@/components/site/Reveal";
import SectionCard from "@/components/site/SectionCard";
import LiveAirPodsCard from "@/components/sections/LiveAirPodsCard";
import InteractiveFolder from "@/components/ui/interactive-folder";
import SkyFeatureCard from "@/components/sections/SkyFeatureCard";
import MusicPlayer from "@/components/ui/music-player";

export default function Features() {
  return (
    <section id="features" className="px-6 py-14 sm:px-10">
      <Reveal className="mx-auto max-w-2xl">
        <SectionCard className="px-4 py-14 text-center sm:px-6">
          <span className="font-mono text-xs font-bold uppercase tracking-[0.25em] text-foreground-muted">
            The rest of it
          </span>
          <h2 className="mt-4 font-display text-7xl font-semibold tracking-tight sm:text-[5.625rem]">
            It keeps <span className="font-black italic">going.</span>
          </h2>
        </SectionCard>
      </Reveal>

      <div className="mx-auto mt-16 grid max-w-5xl gap-5 sm:grid-cols-3 sm:grid-rows-3">
        <Reveal className="sm:col-start-1 sm:row-start-1 sm:row-span-2">
          <LiveAirPodsCard />
        </Reveal>

        <Reveal delay={0.06} className="sm:col-start-2 sm:row-start-1">
          <div className="group flex h-full flex-col items-center justify-between gap-8 rounded-3xl bg-background-soft p-6 text-center transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)]">
            <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
              Still playing, <span className="italic">even locked.</span>
            </h3>
            <div className="flex items-center justify-center gap-2 text-foreground-muted">
              <span className="flex h-6 w-6 items-center justify-center rounded-full border border-foreground/30 text-[10px] transition-transform duration-450 ease-[cubic-bezier(.22,.61,.2,1)] group-hover:-translate-y-1">
                ▶
              </span>
              <span className="text-xs font-medium">
                Locked — still playing
              </span>
            </div>
          </div>
        </Reveal>

        <Reveal delay={0.12} className="sm:col-start-3 sm:row-start-1">
          <SkyFeatureCard />
        </Reveal>

        <Reveal
          delay={0.06}
          className="sm:col-start-2 sm:col-span-2 sm:row-start-2"
        >
          <div className="group flex h-full flex-col justify-between gap-6 rounded-3xl bg-background-soft p-6 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)] sm:flex-row sm:items-center">
            <div>
              <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
                Every <span className="italic">display.</span>
              </h3>
              <p className="mt-2 text-sm text-foreground-muted">
                Externals and Macs without a notch.
              </p>
            </div>
            <div className="flex gap-1.5 text-foreground/60 transition-transform duration-550 ease-[cubic-bezier(.22,.61,.2,1)] group-hover:scale-[1.06]">
              <span className="h-2 w-2 rounded-full bg-current" />
              <span className="h-2 w-2 rounded-full bg-current" />
            </div>
          </div>
        </Reveal>

        <Reveal className="sm:col-start-1 sm:row-start-3">
          <div className="group flex h-full flex-col justify-between gap-6 overflow-hidden rounded-3xl bg-background-soft p-6 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)]">
            <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
              Drop it, <span className="italic">find it later.</span>
            </h3>
            <div className="flex items-end justify-between">
              <span className="text-xs font-medium text-foreground-muted">
                1 item held
              </span>
              <div style={{ width: 45, height: 36 }}>
                <div
                  style={{
                    width: 100,
                    height: 80,
                    transform: "scale(0.45)",
                    transformOrigin: "top left",
                  }}
                >
                  <InteractiveFolder color="#5ac8fa" />
                </div>
              </div>
            </div>
          </div>
        </Reveal>

        <Reveal
          delay={0.12}
          className="sm:col-start-2 sm:col-span-2 sm:row-start-3"
        >
          <div className="group flex h-full flex-col justify-between gap-6 rounded-3xl bg-background-soft p-6 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-1 hover:shadow-[0_16px_40px_-12px_rgba(29,29,31,0.18)] sm:flex-row sm:items-center">
            <div>
              <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
                Now playing, <span className="italic">everywhere.</span>
              </h3>
              <p className="mt-2 text-sm text-foreground-muted">
                Synced lyrics from Spotify or Apple Music, no app-switching.
              </p>
            </div>
            <MusicPlayer
              title="Houdini"
              artist="Dua Lipa"
              className="shrink-0 transition-transform duration-450 ease-[cubic-bezier(.22,.61,.2,1)] group-hover:-translate-y-1"
            />
          </div>
        </Reveal>
      </div>
    </section>
  );
}
