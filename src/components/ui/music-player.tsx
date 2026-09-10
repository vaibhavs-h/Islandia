"use client";

import { useState } from "react";
import { Pause, Play, SkipBack, SkipForward } from "lucide-react";

export interface MusicPlayerProps {
  title: string;
  artist: string;
  coverSrc?: string;
  className?: string;
}

export default function MusicPlayer({
  title,
  artist,
  coverSrc="https://ourculturemag.com/wp-content/uploads/2024/03/RO-album-artwork_DL_Credit-Tyrone-Lebon-scaled.jpg",
  className = "",
}: MusicPlayerProps) {
  const [playing, setPlaying] = useState(true);

  return (
    <div
      className={`flex w-72 items-center gap-3 overflow-hidden rounded-full bg-black px-3 py-2 text-white ${className}`}
    >
      <img
        src={coverSrc}
        alt={`${title} album art`}
        className="h-9 w-9 shrink-0 rounded-full bg-white/10 object-cover"
      />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{title}</p>
        <p className="truncate text-xs text-white/60">{artist}</p>
      </div>
      <button
        type="button"
        onClick={() => setPlaying(false)}
        className="rounded-full p-1 transition-colors hover:bg-white/20"
        aria-label="Previous"
      >
        <SkipBack className="h-4 w-4" />
      </button>
      <button
        type="button"
        onClick={() => setPlaying((p) => !p)}
        className="rounded-full p-1 transition-colors hover:bg-white/20"
        aria-label={playing ? "Pause" : "Play"}
      >
        {playing ? (
          <Pause className="h-4 w-4" />
        ) : (
          <Play className="h-4 w-4" />
        )}
      </button>
      <button
        type="button"
        onClick={() => setPlaying(true)}
        className="rounded-full p-1 transition-colors hover:bg-white/20"
        aria-label="Next"
      >
        <SkipForward className="h-4 w-4" />
      </button>
    </div>
  );
}
