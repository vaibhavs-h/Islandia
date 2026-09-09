"use client";

import { useState } from "react";
import Reveal from "@/components/site/Reveal";

export default function CTA() {
  const [submitted, setSubmitted] = useState(false);

  return (
    <section id="pricing" className="px-6 py-14 sm:px-10">
      <Reveal className="mx-auto flex max-w-xl flex-col items-center rounded-3xl bg-background-soft px-8 py-14 text-center">
        <h2 className="font-display text-3xl font-semibold tracking-tight sm:text-4xl">
          Be first to know.
        </h2>
        <p className="mt-4 max-w-sm text-foreground-muted">
          One-time purchase, no subscription — just like it should be. Leave
          your email and we&rsquo;ll tell you the moment Islandia is ready to
          download.
        </p>

        {submitted ? (
          <p className="mt-8 text-sm font-medium text-accent-rust-dark">
            You&rsquo;re on the list — thanks for the early interest.
          </p>
        ) : (
          <form
            id="notify"
            onSubmit={(e) => {
              e.preventDefault();
              setSubmitted(true);
            }}
            className="mt-8 flex w-full max-w-sm flex-col gap-3 sm:flex-row"
          >
            <input
              type="email"
              required
              placeholder="you@example.com"
              className="w-full flex-1 rounded-full border border-foreground/15 bg-background px-5 py-3 text-sm outline-none focus:border-foreground/40"
            />
            <button
              type="submit"
              className="rounded-full bg-foreground px-6 py-3 text-sm font-medium text-background transition-opacity hover:opacity-85"
            >
              Notify me
            </button>
          </form>
        )}
      </Reveal>
    </section>
  );
}
