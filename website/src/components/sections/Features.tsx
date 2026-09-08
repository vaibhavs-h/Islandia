import Reveal from "@/components/site/Reveal";

type Feature = {
  title: string;
  description: string;
  chip: React.ReactNode;
};

const features: Feature[] = [
  {
    title: "Now Playing, with lyrics",
    description:
      "Live track info and synced lyrics from Spotify, Apple Music, or whatever's playing — right at the top of your screen, no app-switching.",
    chip: (
      <div className="flex items-center gap-2">
        <span className="text-sm">♪</span>
        <div className="flex flex-col gap-1">
          <span className="text-[11px] font-medium leading-none">
            Sundown
          </span>
          <span className="text-[10px] leading-none text-white/60">
            Islandia Radio
          </span>
        </div>
      </div>
    ),
  },
  {
    title: "Lock screen music",
    description:
      "See what's playing and control it before you've even logged in.",
    chip: (
      <div className="flex items-center gap-2">
        <span className="flex h-4 w-4 items-center justify-center rounded-full border border-white/40 text-[9px]">
          ▶
        </span>
        <span className="text-[11px] font-medium">Locked — still playing</span>
      </div>
    ),
  },
  {
    title: "AirPods battery",
    description:
      "Live battery level for AirPods Pro/Max the moment they connect. No digging through System Settings.",
    chip: (
      <div className="flex items-center gap-2">
        <span className="text-sm">🎧</span>
        <span className="text-[11px] font-medium">82%</span>
      </div>
    ),
  },
  {
    title: "Weather, glanceable",
    description: "Current conditions, always visible, never a separate app.",
    chip: (
      <div className="flex items-center gap-2">
        <span className="text-sm">☀︎</span>
        <span className="text-[11px] font-medium">72°</span>
      </div>
    ),
  },
  {
    title: "File shelf",
    description:
      "Drop a file onto the island, grab it later from anywhere — a temporary holding spot instead of desktop clutter.",
    chip: (
      <div className="flex items-center gap-2">
        <span className="text-sm">📄</span>
        <span className="text-[11px] font-medium">1 item held</span>
      </div>
    ),
  },
  {
    title: "Multi-display",
    description:
      "Works on external monitors and notch-less Macs too — not just newer MacBooks.",
    chip: (
      <div className="flex items-center gap-1.5">
        <span className="h-2 w-2 rounded-full bg-white/70" />
        <span className="h-2 w-2 rounded-full bg-white/70" />
      </div>
    ),
  },
];

export default function Features() {
  return (
    <section id="features" className="px-6 py-28 sm:px-10">
      <Reveal className="mx-auto max-w-2xl text-center">
        <h2 className="font-display text-3xl font-semibold tracking-tight sm:text-4xl">
          Everything you kept switching apps for.
        </h2>
        <p className="mt-4 text-foreground-muted">
          One persistent, elegant surface at the top of your screen —
          consolidating the small daily annoyances into a single glance.
        </p>
      </Reveal>

      <div className="mx-auto mt-16 grid max-w-5xl gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {features.map((feature, i) => (
          <Reveal key={feature.title} delay={(i % 3) * 0.08}>
            <div className="flex h-full flex-col gap-5 rounded-3xl bg-background-soft p-6">
              <div className="flex h-16 w-fit items-center rounded-full bg-black/90 px-4 text-white">
                {feature.chip}
              </div>
              <div>
                <h3 className="font-medium text-foreground">
                  {feature.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed text-foreground-muted">
                  {feature.description}
                </p>
              </div>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
