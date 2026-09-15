import { useRef, useEffect, useState, type CSSProperties } from 'react';

type Strategy = 'auto' | 'name' | 'email' | 'monoId';

interface ResponsiveTextProps {
  children: string;
  /** How to shorten the text when it overflows. */
  strategy?: Strategy;
  /** Minimum font-size in px before shortening kicks in. */
  minFontSize?: number;
  /** Maximum number of lines before applying responsive logic (default: 1). */
  maxLines?: number;
  /** Extra CSS class names. */
  className?: string;
  /** Override inline styles. */
  style?: CSSProperties;
  /** Render as a specific HTML element (default: span). */
  as?: 'span' | 'p' | 'h1' | 'h2' | 'h3' | 'div';
  /** When true, always show a title tooltip with the full text. */
  alwaysTooltip?: boolean;
}

/**
 * Intelligently shorten text when it doesn't fit its container.
 *
 * Priority order:
 *  1. Show the full text if it fits.
 *  2. Allow wrapping up to `maxLines`.
 *  3. If a single line and still too long, try reducing font-size
 *     down to `minFontSize`.
 *  4. Apply strategy-aware shortening:
 *     - `name`: "VinFast Lux A2.0 Premium" → "Lux A2.0 Premium" → "Lux A2.0"
 *     - `email`: "longname@example.com" → "long…@example.com"
 *     - `monoId`: "abc123def456ghi" → "abc12…6ghi"
 *     - `auto`: try `name`, fall back to middle-truncation
 */
function shorten(text: string, strategy: Strategy, pass: number): string {
  if (!text || pass <= 0) return text;

  switch (strategy) {
    case 'name': {
      // Remove first word (brand) on pass 1, then last word on pass 2+
      const parts = text.split(/\s+/);
      if (parts.length <= 1) return text;
      if (pass === 1) return parts.slice(1).join(' ');
      if (pass === 2 && parts.length > 2) return parts.slice(1, -1).join(' ');
      return parts.slice(1).join(' ');
    }
    case 'email': {
      const at = text.indexOf('@');
      if (at <= 3) return text;
      const keep = Math.max(2, Math.floor(at / 2) - pass);
      return text.slice(0, keep) + '…' + text.slice(at);
    }
    case 'monoId': {
      if (text.length <= 10) return text;
      const keep = Math.max(4, Math.floor(text.length / 2) - pass * 2);
      const half = Math.floor(keep / 2);
      return text.slice(0, half) + '…' + text.slice(-half);
    }
    case 'auto':
    default: {
      // If text has spaces, try name strategy first
      if (text.includes(' ') && pass <= 2) {
        return shorten(text, 'name', pass);
      }
      // Fall back to middle truncation
      if (text.length <= 8) return text;
      const keep = Math.max(6, text.length - pass * 3);
      const half = Math.floor(keep / 2);
      return text.slice(0, half) + '…' + text.slice(-half);
    }
  }
}

export function ResponsiveText({
  children,
  strategy = 'auto',
  minFontSize = 11,
  maxLines = 1,
  className = '',
  style,
  as: Tag = 'span',
  alwaysTooltip = false,
}: ResponsiveTextProps) {
  const ref = useRef<HTMLElement>(null);
  const [display, setDisplay] = useState(children);
  const [fontSize, setFontSize] = useState<number | undefined>(undefined);
  const shortened = display !== children;

  useEffect(() => {
    setDisplay(children);
    setFontSize(undefined);
  }, [children]);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    // Allow layout to settle
    const frame = requestAnimationFrame(() => {
      if (!el.parentElement) return;
      const isOverflowing = el.scrollWidth > el.parentElement.clientWidth + 1;
      if (!isOverflowing) return;

      // Step 1: Try reducing font-size
      const computed = parseFloat(getComputedStyle(el).fontSize);
      if (computed > minFontSize && maxLines === 1) {
        setFontSize(Math.max(minFontSize, computed - 1));
        return;
      }

      // Step 2: Apply strategy shortening
      for (let pass = 1; pass <= 4; pass++) {
        const candidate = shorten(children, strategy, pass);
        if (candidate === display || candidate.length >= display.length) continue;
        setDisplay(candidate);
        return;
      }
    });

    return () => cancelAnimationFrame(frame);
  }, [children, display, fontSize, strategy, minFontSize, maxLines]);

  const inlineStyle: CSSProperties = {
    ...style,
    ...(fontSize ? { fontSize: `${fontSize}px` } : {}),
    ...(maxLines > 1
      ? {
          display: '-webkit-box',
          WebkitLineClamp: maxLines,
          WebkitBoxOrient: 'vertical' as const,
          overflow: 'hidden',
        }
      : { whiteSpace: 'nowrap' as const }),
  };

  return (
    <Tag
      ref={ref as any}
      className={className}
      style={inlineStyle}
      title={(alwaysTooltip || shortened) ? children : undefined}
    >
      {display}
    </Tag>
  );
}

export default ResponsiveText;
