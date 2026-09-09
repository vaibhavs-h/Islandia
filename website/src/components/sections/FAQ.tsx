import Reveal from "@/components/site/Reveal";
import SectionCard from "@/components/site/SectionCard";

const faqs = [
  {
    q: "Will this drain my battery?",
    a: "It's built to be event-driven, not polling — Islandia reacts to system events (a new track, a battery update) instead of checking on a timer, so it sits at near-zero CPU and memory when idle.",
  },
  {
    q: "Is this a subscription?",
    a: "No. The plan is a one-time purchase, the same way the product that inspired this one works — not a recurring charge.",
  },
  {
    q: "What data do you collect?",
    a: "As little as possible, by design — no analytics, no telemetry. Now Playing and lyrics data stays on your Mac.",
  },
  {
    q: "Does it work without a notch?",
    a: "Yes — multi-display and notch-less Mac support is part of the core plan, not an afterthought bolted on later.",
  },
  {
    q: "When can I download it?",
    a: "Islandia is still in active development. Sign up below and you'll hear the moment it's ready.",
  },
];

export default function FAQ() {
  return (
    <section id="faq" className="px-6 py-14 sm:px-10">
      <Reveal className="mx-auto max-w-2xl">
        <SectionCard className="px-4 py-14 text-center sm:px-6">
          <span className="font-mono text-xs font-bold uppercase tracking-[0.25em] text-foreground-muted">
            Fair questions
          </span>
          <h2 className="mt-4 font-display text-7xl font-semibold tracking-tight sm:text-[5.625rem]">
            Before you <span className="font-black italic">ask.</span>
          </h2>
        </SectionCard>
      </Reveal>

      <Reveal className="mx-auto mt-16 max-w-2xl divide-y divide-foreground/10">
        {faqs.map((faq, i) => (
          <details key={faq.q} className="group py-6">
            <summary className="flex cursor-pointer list-none items-start justify-between gap-6 text-left">
              <span className="flex items-baseline gap-4">
                <span className="font-mono text-xs text-foreground-muted">
                  {String(i + 1).padStart(2, "0")}
                </span>
                <span className="font-medium text-foreground">{faq.q}</span>
              </span>
              <span className="shrink-0 text-lg font-light leading-none text-foreground-muted transition-transform group-open:rotate-45">
                +
              </span>
            </summary>
            <p className="mt-3 pl-8 text-sm leading-relaxed text-foreground-muted">
              {faq.a}
            </p>
          </details>
        ))}
      </Reveal>
    </section>
  );
}
