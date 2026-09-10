"use client";

import React, { useState, CSSProperties, MouseEvent } from "react";

interface InteractiveFolderProps {
  /** The main color of the folder. Defaults to #00d8ff. */
  color?: string;
  /** The scale factor for the component size. Defaults to 1. */
  scale?: number;
  /** An array of React nodes to display inside the folder. Up to 3 items will be shown. */
  items?: React.ReactNode[];
  /** Optional additional CSS class name for the outer container. */
  className?: string;
}

/**
 * Adjusts the brightness of a hex color value.
 * @param hex The hex color string (e.g., "#RRGGBB" or "#RGB").
 * @param amount A value between 0 and 1, where 0 is the same brightness and 1 is completely black.
 * @returns The adjusted hex color string.
 */
const adjustHexBrightness = (hex: string, amount: number): string => {
  let s = hex.startsWith("#") ? hex.slice(1) : hex;
  if (s.length === 3) {
    s = s
      .split("")
      .map((c) => c + c)
      .join("");
  }
  const n = parseInt(s, 16);
  let r = (n >> 16) & 0xff;
  let g = (n >> 8) & 0xff;
  let b = n & 0xff;
  r = Math.max(0, Math.min(255, Math.floor(r * (1 - amount))));
  g = Math.max(0, Math.min(255, Math.floor(g * (1 - amount))));
  b = Math.max(0, Math.min(255, Math.floor(b * (1 - amount))));
  return (
    "#" +
    ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1).toUpperCase()
  );
};

/**
 * An interactive folder component that opens to reveal items.
 */
const InteractiveFolder: React.FC<InteractiveFolderProps> = ({
  color = "#00d8ff",
  scale = 1,
  items = [],
  className = "",
}) => {
  const maxItems = 3;
  let displayedItems = items.slice(0, maxItems);

  // Pad displayedItems with nulls if needed to always have maxItems slots
  while (displayedItems.length < maxItems) {
    displayedItems.push(null);
  }

  // State for whether the folder is open or closed
  const [isOpen, setIsOpen] = useState(false);
  // State for the offset of each item due to mouse interaction
  const [itemOffsets, setItemOffsets] = useState<{ x: number; y: number }[]>(
    Array.from({ length: maxItems }, () => ({ x: 0, y: 0 }))
  );

  // Derived colors for folder parts and items
  const folderBackColor = adjustHexBrightness(color, 0.08);
  const paperColor1 = adjustHexBrightness("#ffffff", 0.35);
  const paperColor2 = adjustHexBrightness("#ffffff", 0.25);
  const paperColor3 = adjustHexBrightness("#ffffff", 0.15);

  // Handle click event on the main folder area
  const handleFolderClick = () => {
    setIsOpen((prev) => !prev);
    if (isOpen) {
      // If closing, reset the item offsets
      setItemOffsets(Array.from({ length: maxItems }, () => ({ x: 0, y: 0 })));
    }
  };

  // Handle mouse move event on an item when the folder is open
  const handleItemMouseMove = (
    e: MouseEvent<HTMLDivElement>,
    index: number
  ) => {
    if (!isOpen) return; // Only active when open
    const itemRect = e.currentTarget.getBoundingClientRect();
    const centerX = itemRect.left + itemRect.width / 2;
    const centerY = itemRect.top + itemRect.height / 2;
    const offsetX = (e.clientX - centerX) * 0.15; // Calculate offset based on mouse position relative to item center
    const offsetY = (e.clientY - centerY) * 0.15;
    setItemOffsets((currentOffsets) => {
      const updatedOffsets = [...currentOffsets];
      updatedOffsets[index] = { x: offsetX, y: offsetY };
      return updatedOffsets;
    });
  };

  // Handle mouse leave event on an item when the folder is open
  const handleItemMouseLeave = (
    e: MouseEvent<HTMLDivElement>,
    index: number
  ) => {
    // Reset the offset for the specific item
    setItemOffsets((currentOffsets) => {
      const updatedOffsets = [...currentOffsets];
      updatedOffsets[index] = { x: 0, y: 0 };
      return updatedOffsets;
    });
  };

  // CSS variables passed via style prop
  const folderStyles: CSSProperties = {
    "--main-component-color": color,
    "--back-component-color": folderBackColor,
    "--piece-color-1": paperColor1,
    "--piece-color-2": paperColor2,
    "--piece-color-3": paperColor3,
  } as CSSProperties;

  // Style for the outer wrapper to apply scale
  const scaleStyle = { transform: `scale(${scale})` };

  // Calculate the initial transform for an item when the folder is open
  const getOpenItemTransform = (itemIndex: number) => {
    if (itemIndex === 0) return "translate(-120%, -70%) rotate(-15deg)";
    if (itemIndex === 1) return "translate(10%, -70%) rotate(15deg)";
    if (itemIndex === 2) return "translate(-50%, -100%) rotate(5deg)";
    return ""; // Should not happen with maxItems = 3
  };

  return (
    // Outer div for applying scale and external class name. Its own box
    // never moves (only the folder inside it lifts on open), so it's a
    // stable boundary for detecting "the pointer left the feature box" —
    // attaching this to the folder itself would self-trigger, since the
    // lift transform shifts that element out from under a stationary cursor.
    <div
      style={scaleStyle}
      className={className}
      onMouseLeave={() => {
        // Always snap back to closed once the pointer leaves, even if it
        // was opened via click rather than hover.
        setIsOpen(false);
        setItemOffsets(Array.from({ length: maxItems }, () => ({ x: 0, y: 0 })));
      }}
    >
      {/* Main container div for the folder visual */}
      <div
        className={`group relative transition-all duration-200 ease-in cursor-pointer ${
          // Apply hover effect only when closed
          !isOpen ? "hover:-translate-y-2" : ""
        }`}
        // Apply internal styles and click handler
        style={{
          ...folderStyles,
          // Apply a slight lift transform when open
          transform: isOpen ? "translateY(-8px)" : undefined,
        }}
        onClick={handleFolderClick}
      >
        {/* Back part of the folder */}
        <div
          className="relative w-[100px] h-[80px] rounded-tl-0 rounded-tr-[10px] rounded-br-[10px] rounded-bl-[10px]"
          style={{ backgroundColor: folderBackColor }}
        >
          {/* Small tab on top */}
          <span
            className="absolute z-0 bottom-[98%] left-0 w-[30px] h-[10px] rounded-tl-[5px] rounded-tr-[5px] rounded-bl-0 rounded-br-0"
            style={{ backgroundColor: folderBackColor }}
          ></span>

          {/* Render content items (papers) */}
          {displayedItems.map((item, index) => {
            let itemSizeClasses = "";
            // Determine size classes based on index and open/closed state
            if (index === 0) itemSizeClasses = isOpen ? "w-[70%] h-[80%]" : "w-[70%] h-[80%]";
            if (index === 1) itemSizeClasses = isOpen ? "w-[80%] h-[80%]" : "w-[80%] h-[70%]";
            if (index === 2) itemSizeClasses = isOpen ? "w-[90%] h-[80%]" : "w-[90%] h-[60%]";

            // Calculate the combined transform based on open state and mouse position
            const itemTransformStyle = isOpen
              ? `${getOpenItemTransform(index)} translate(${itemOffsets[index].x}px, ${itemOffsets[index].y}px)` // Apply open and mouse offset transform
              : undefined; // No dynamic transform when closed

            return (
              // Individual content item div
              <div
                key={index} // Use index as key
                onMouseMove={(e) => handleItemMouseMove(e, index)} // Attach mouse move handler
                onMouseLeave={(e) => handleItemMouseLeave(e, index)} // Attach mouse leave handler
                className={`absolute z-20 bottom-[10%] left-1/2 transition-all duration-300 ease-in-out ${
                  // Apply transform for closed state and hover effect
                  !isOpen
                    ? "transform -translate-x-1/2 translate-y-[10%] group-hover:translate-y-0"
                    : "hover:scale-110" // Apply hover scale effect when open
                } ${itemSizeClasses}`} // Apply calculated size classes
                // Apply dynamic styles (transform and background color)
                style={{
                  ...(!isOpen ? {} : { transform: itemTransformStyle }), // Apply dynamic transform only when open
                  backgroundColor: index === 0 ? paperColor1 : index === 1 ? paperColor2 : paperColor3, // Apply dynamic background color
                  borderRadius: "10px", // Apply border radius
                }}
              >
                {item} {/* Render the actual content */}
              </div>
            );
          })}

          {/* Front top part of the folder (left skew piece) */}
          <div
            className={`absolute z-30 w-full h-full origin-bottom transition-all duration-300 ease-in-out ${
              // Apply hover skew transform when closed
              !isOpen ? "group-hover:[transform:skew(15deg)_scaleY(0.6)]" : ""
            }`}
            style={{
              backgroundColor: color, // Apply main color
              borderRadius: "5px 10px 10px 10px",
              ...(isOpen && { transform: "skew(15deg) scaleY(0.6)" }), // Apply open skew transform
            }}
          ></div>

          {/* Front top part of the folder (right skew piece) */}
          <div
            className={`absolute z-30 w-full h-full origin-bottom transition-all duration-300 ease-in-out ${
              // Apply hover skew transform when closed
              !isOpen ? "group-hover:[transform:skew(-15deg)_scaleY(0.6)]" : ""
            }`}
            style={{
              backgroundColor: color, // Apply main color
              borderRadius: "5px 10px 10px 10px",
              ...(isOpen && { transform: "skew(-15deg) scaleY(0.6)" }), // Apply open skew transform
            }}
          ></div>
        </div>
      </div>
    </div>
  );
};

export default InteractiveFolder;
