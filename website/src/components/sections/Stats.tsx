import Reveal from "@/components/site/Reveal";

const principles = [
  {
    title: "Event-driven",
    body: "Never polling. Islandia reacts to system events — a new track, a battery update — instead of checking on a timer.",
  },
  {
    title: "Native bridge",
    body: "A thin Swift layer talks directly to MediaRemote, CoreBluetooth, and IOKit. No scraping, no workarounds.",
  },
  {
    title: "Built to disappear",
    body: "No dock icon. No window to manage. Nothing to close. It does nothing at all, until something changes.",
  },
];

export default function Stats() {
  return (
    <section className="bg-foreground px-6 py-24 text-background sm:px-10">
      <Reveal className="mx-auto max-w-2xl text-center">
        <h2 className="font-display text-3xl font-semibold tracking-tight sm:text-4xl">
          Designed to sit at near-zero.
        </h2>
        <p className="mt-4 text-background/70">
          Performance is a first-class feature, not an afterthought —
          benchmarks land here once the app ships.
        </p>
      </Reveal>

      <div className="mx-auto mt-16 grid max-w-4xl gap-8 sm:grid-cols-3">
        {principles.map((principle, i) => (
          <Reveal key={principle.title} delay={i * 0.1}>
            <div className="text-center sm:text-left">
              <h3 className="font-display text-lg font-semibold">
                {principle.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-background/70">
                {principle.body}
              </p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
