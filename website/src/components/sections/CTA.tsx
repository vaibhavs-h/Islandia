import Reveal from "@/components/site/Reveal";
import SectionCard from "@/components/site/SectionCard";
import AppleMark from "@/components/site/AppleMark";

export default function CTA() {
  return (
    <section id="pricing" className="px-6 py-14 sm:px-10">
      <Reveal className="mx-auto max-w-3xl">
        <SectionCard className="px-8 py-14 text-center">
          <span className="font-mono text-xs font-bold uppercase tracking-[0.25em] text-foreground-muted">
            One more scroll saved
          </span>
          <h2 className="mt-4 font-display text-7xl font-semibold tracking-tight sm:text-[5.625rem]">
            Give the top of your screen{" "}
            <span className="font-black italic">a job.</span>
          </h2>
          <p className="mt-4 text-foreground-muted">
            Download Islandia for macOS.
          </p>

          <div className="mt-8 flex flex-wrap items-center justify-center gap-4">
            <a
              href="#"
              className="flex items-center gap-2.5 rounded-full bg-foreground px-6.25 py-3 text-sm font-medium text-background transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:scale-[1.03] hover:opacity-85 active:scale-95"
            >
              <AppleMark className="h-4 w-4" />
              Download for Mac
            </a>
            <a
              href="#"
              className="text-sm font-medium text-foreground underline underline-offset-4 transition-all duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] hover:opacity-70 active:scale-95"
            >
              Recover a license
            </a>
          </div>
        </SectionCard>
      </Reveal>
    </section>
  );
}
