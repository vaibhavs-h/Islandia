import type { ReactNode } from "react";
import { DotPattern } from "@/components/ui/dot-pattern";

export default function SectionCard({
  children,
  className,
  dotClassName,
}: {
  children: ReactNode;
  className?: string;
  dotClassName?: string;
}) {
  return (
    <div className={`relative border-2 border-[crimson] ${className ?? ""}`}>
      <DotPattern
        width={16}
        height={16}
        cr={1}
        className={dotClassName ?? "fill-foreground/15"}
      />
      <span className="absolute -top-[9px] -left-[9px] h-[18px] w-[18px] bg-[crimson]" />
      <span className="absolute -top-[9px] -right-[9px] h-[18px] w-[18px] bg-[crimson]" />
      <span className="absolute -bottom-[9px] -left-[9px] h-[18px] w-[18px] bg-[crimson]" />
      <span className="absolute -bottom-[9px] -right-[9px] h-[18px] w-[18px] bg-[crimson]" />
      <div className="relative">{children}</div>
    </div>
  );
}
