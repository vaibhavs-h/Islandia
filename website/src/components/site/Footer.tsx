import AppleMark from "@/components/site/AppleMark";

export default function Footer() {
  return (
    <footer className="bg-foreground px-6 py-6 sm:px-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 text-sm text-background/60 sm:flex-row">
        <div className="flex items-center gap-6">
          <span className="flex items-center gap-1.5 font-display font-semibold text-background">
            <AppleMark className="h-4 w-4" />
            Islandia
          </span>
          <a href="#features" className="transition-colors hover:text-background">
            Features
          </a>
          <a href="#pricing" className="transition-colors hover:text-background">
            Pricing
          </a>
          <a href="#faq" className="transition-colors hover:text-background">
            FAQ
          </a>
        </div>
        <span className="font-mono text-xs tracking-[0.15em] uppercase text-background/50">
          Made for Macs.
        </span>
      </div>
    </footer>
  );
}
