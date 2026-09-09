import Reveal from "@/components/site/Reveal";
import SectionCard from "@/components/site/SectionCard";

function BatteryRing({ progress }: { progress: number }) {
  const r = 8;
  const c = 2 * Math.PI * r;
  return (
    <svg width="20" height="20" viewBox="0 0 20 20" className="-rotate-90">
      <circle
        cx="10"
        cy="10"
        r={r}
        fill="none"
        stroke="rgba(255,255,255,0.2)"
        strokeWidth="2.5"
      />
      <circle
        cx="10"
        cy="10"
        r={r}
        fill="none"
        stroke="#34d399"
        strokeWidth="2.5"
        strokeDasharray={c}
        strokeDashoffset={c * (1 - progress)}
        strokeLinecap="round"
      />
    </svg>
  );
}

function VolumeTrack({ level }: { level: number }) {
  return (
    <div className="flex items-center gap-2">
      <div className="relative h-1 w-14 rounded-full bg-white/25">
        <span
          className="absolute top-1/2 h-2 w-2 -translate-y-1/2 rounded-full bg-red-500"
          style={{ left: `${level * 100}%` }}
        />
      </div>
      <span className="text-xs text-white/70">10</span>
    </div>
  );
}

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
          <div className="flex h-full flex-col gap-8 rounded-3xl bg-background-soft p-7">
            <div>
              <h3 className="font-display text-2xl font-semibold tracking-tight text-foreground">
                Every pair, <span className="italic">always visible.</span>
              </h3>
              <p className="mt-3 text-sm leading-relaxed text-foreground-muted">
                Battery and volume, the moment they connect.
              </p>
            </div>
            <div className="mt-auto flex flex-col gap-3">
              <div className="flex items-center justify-between rounded-full bg-black px-5 py-3.5 text-white">
                <div className="flex items-center gap-3">
                  <span className="text-base">🎧</span>
                  <span className="text-sm font-medium">AirPods Pro</span>
                </div>
                <BatteryRing progress={0.7} />
              </div>
              <div className="flex items-center justify-between rounded-full bg-black px-5 py-3.5 text-white">
                <div className="flex items-center gap-3">
                  <span className="text-base">🎧</span>
                  <span className="text-sm font-medium">AirPods Max</span>
                </div>
                <VolumeTrack level={0.15} />
              </div>
            </div>
          </div>
        </Reveal>

        <Reveal delay={0.06} className="sm:col-start-2 sm:row-start-1">
          <div className="flex h-full flex-col justify-between gap-8 rounded-3xl bg-background-soft p-6">
            <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
              Still playing, <span className="italic">even locked.</span>
            </h3>
            <div className="flex items-center gap-2 text-foreground-muted">
              <span className="flex h-6 w-6 items-center justify-center rounded-full border border-foreground/30 text-[10px]">
                ▶
              </span>
              <span className="text-xs font-medium">
                Locked — still playing
              </span>
            </div>
          </div>
        </Reveal>

        <Reveal delay={0.12} className="sm:col-start-3 sm:row-start-1">
          <div className="flex h-full flex-col justify-between gap-8 rounded-3xl bg-background-soft p-6">
            <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
              The sky, <span className="italic">up top.</span>
            </h3>
            <div className="flex items-center gap-2 text-foreground">
              <span className="text-lg">☀︎</span>
              <span className="text-2xl font-semibold">72°</span>
            </div>
          </div>
        </Reveal>

        <Reveal
          delay={0.06}
          className="sm:col-start-2 sm:col-span-2 sm:row-start-2"
        >
          <div className="flex h-full flex-col justify-between gap-6 rounded-3xl bg-background-soft p-6 sm:flex-row sm:items-center">
            <div>
              <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
                Every <span className="italic">display.</span>
              </h3>
              <p className="mt-2 text-sm text-foreground-muted">
                Externals and Macs without a notch.
              </p>
            </div>
            <div className="flex gap-1.5 text-foreground/60">
              <span className="h-2 w-2 rounded-full bg-current" />
              <span className="h-2 w-2 rounded-full bg-current" />
            </div>
          </div>
        </Reveal>

        <Reveal className="sm:col-start-1 sm:row-start-3">
          <div className="flex h-full flex-col justify-between gap-6 rounded-3xl bg-background-soft p-6">
            <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
              Drop it, <span className="italic">find it later.</span>
            </h3>
            <div className="flex items-center gap-2 text-foreground-muted">
              <span className="text-lg">📄</span>
              <span className="text-xs font-medium">1 item held</span>
            </div>
          </div>
        </Reveal>

        <Reveal
          delay={0.12}
          className="sm:col-start-2 sm:col-span-2 sm:row-start-3"
        >
          <div className="flex h-full flex-col justify-between gap-6 rounded-3xl bg-background-soft p-6 sm:flex-row sm:items-center">
            <div>
              <h3 className="font-display text-lg font-semibold tracking-tight text-foreground">
                Now playing, <span className="italic">everywhere.</span>
              </h3>
              <p className="mt-2 text-sm text-foreground-muted">
                Synced lyrics from Spotify or Apple Music, no app-switching.
              </p>
            </div>
            <div className="flex items-center gap-2 rounded-full bg-black px-4 py-2.5 text-white">
              <span className="text-sm">♪</span>
              <div className="flex flex-col gap-0.5">
                <span className="text-[11px] font-medium leading-none">
                  Sundown
                </span>
                <span className="text-[10px] leading-none text-white/60">
                  Islandia Radio
                </span>
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
