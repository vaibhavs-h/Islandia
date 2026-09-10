import AppleMark from "@/components/site/AppleMark";
import Reveal from "@/components/site/Reveal";

export default function Footer() {
  return (
    <footer className="bg-foreground px-[117.6px] py-15">
      <Reveal
        margin="0px"
        className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-background/60 sm:flex-row"
      >
        <div className="flex items-center gap-6">
          <span className="flex items-center gap-1.5 font-display font-semibold text-background">
            <AppleMark className="h-4 w-4" />
            Islandia
          </span>
          <a
            href="#features"
            className="transition-colors duration-200 hover:text-background"
          >
            Features
          </a>
          <a
            href="#pricing"
            className="transition-colors duration-200 hover:text-background"
          >
            Pricing
          </a>
          <a
            href="#faq"
            className="transition-colors duration-200 hover:text-background"
          >
            FAQ
          </a>
        </div>
        <span className="font-mono text-xs tracking-[0.15em] uppercase text-background/50">
          Made for Macs.
        </span>
      </Reveal>
    </footer>
  );
}
