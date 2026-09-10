"use client";

import { motion } from "framer-motion";
import type { ReactNode } from "react";

export default function Reveal({
  children,
  delay = 0,
  className,
  margin = "-80px",
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
  /**
   * Shrinks (negative) or grows (positive) the viewport used to decide when
   * this has scrolled into view. The default works well for sections with
   * room to scroll past, but the very last element on a page can never be
   * scrolled far enough to satisfy a negative margin — there's no more
   * document below it — so it would stay invisible forever. Pass something
   * lenient (e.g. "0px") for a page's final section.
   */
  margin?: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin }}
      transition={{ duration: 0.6, delay, ease: [0.22, 1, 0.36, 1] }}
      className={className}
    >
      {children}
    </motion.div>
  );
}
