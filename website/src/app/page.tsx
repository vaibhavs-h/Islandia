import Footer from "@/components/site/Footer";
import Features from "@/components/sections/Features";
import Stats from "@/components/sections/Stats";
import FAQ from "@/components/sections/FAQ";
import CTA from "@/components/sections/CTA";

export default function Home() {
  return (
    <div className="flex flex-1 flex-col">
      <Features />
      <Stats />
      <FAQ />
      <CTA />
      <Footer />
    </div>
  );
}
