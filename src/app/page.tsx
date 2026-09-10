import Footer from "@/components/site/Footer";
import Hero from "@/components/hero/Hero";
import Features from "@/components/sections/Features";
import FAQ from "@/components/sections/FAQ";
import CTA from "@/components/sections/CTA";

export default function Home() {
  return (
    <div className="flex flex-1 flex-col">
      <Hero />
      <Features />
      <FAQ />
      <CTA />
      <Footer />
    </div>
  );
}
