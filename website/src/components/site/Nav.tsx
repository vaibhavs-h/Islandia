"use client";

import { useEffect, useState } from "react";

export default function Nav() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    function checkPastHero() {
      const hero = document.getElementById("hero");
      if (!hero) return;
      setVisible(hero.getBoundingClientRect().bottom <= 0);
    }
    checkPastHero();
    window.addEventListener("scroll", checkPastHero, { passive: true });
    window.addEventListener("resize", checkPastHero);
    return () => {
      window.removeEventListener("scroll", checkPastHero);
      window.removeEventListener("resize", checkPastHero);
    };
  }, []);

  return (
    <div
      className={`fixed inset-x-0 top-0 z-50 flex items-center justify-between border-b px-6 py-4 backdrop-blur-md transition-all duration-300 sm:px-10 ${
        visible
          ? "border-foreground/10 bg-background/80 opacity-100"
          : "pointer-events-none border-transparent bg-transparent opacity-0"
      }`}
    >
      <span className="font-display text-sm font-semibold tracking-tight text-foreground">
        Islandia
      </span>
      <nav className="hidden items-center gap-6 text-sm text-foreground-muted sm:flex">
        <a href="#features" className="transition-colors hover:text-foreground">
          Features
        </a>
        <a href="#pricing" className="transition-colors hover:text-foreground">
          Pricing
        </a>
        <a href="#faq" className="transition-colors hover:text-foreground">
          FAQ
        </a>
      </nav>
      <a
        href="#notify"
        className="rounded-full bg-foreground px-4 py-2 text-xs font-medium text-background ring-1 ring-background/15 transition-opacity hover:opacity-85"
      >
        Get notified
      </a>
    </div>
  );
}
