import Reveal from "@/components/site/Reveal";

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
    <section id="faq" className="px-6 py-28 sm:px-10">
      <Reveal className="mx-auto max-w-2xl text-center">
        <h2 className="font-display text-3xl font-semibold tracking-tight sm:text-4xl">
          Questions, answered.
        </h2>
      </Reveal>

      <Reveal className="mx-auto mt-12 max-w-2xl divide-y divide-foreground/10">
        {faqs.map((faq) => (
          <details key={faq.q} className="group py-5">
            <summary className="flex cursor-pointer list-none items-center justify-between text-left font-medium text-foreground">
              {faq.q}
              <span className="ml-4 text-foreground-muted transition-transform group-open:rotate-45">
                +
              </span>
            </summary>
            <p className="mt-3 text-sm leading-relaxed text-foreground-muted">
              {faq.a}
            </p>
          </details>
        ))}
      </Reveal>
    </section>
  );
}
