import { useId } from 'react';

/** Pinova mark (QA 133): a "P" made of the app's charge dial — platinum ring
 * on a stem, the last stretch lit emerald, a white knob at its end. */
export function PinovaMark({ className, tile = false }: { className?: string; tile?: boolean }) {
  const id = useId().replace(/:/g, '');
  return (
    <svg viewBox="0 0 512 512" className={className} role="img" aria-label="Pinova">
      <defs>
        <radialGradient id={`bg-${id}`} cx="50%" cy="38%" r="75%">
          <stop offset="0" stopColor="#1D1F22" />
          <stop offset="1" stopColor="#050506" />
        </radialGradient>
        <linearGradient id={`pt-${id}`} gradientUnits="userSpaceOnUse" x1="96" y1="80" x2="420" y2="440">
          <stop offset="0" stopColor="#F7F7F5" />
          <stop offset=".55" stopColor="#D6D8DB" />
          <stop offset="1" stopColor="#9EA2A8" />
        </linearGradient>
      </defs>
      {tile && <rect width="512" height="512" rx="112" fill={`url(#bg-${id})`} />}
      <path d="M146 412V210" stroke={`url(#pt-${id})`} strokeWidth="46" strokeLinecap="round" fill="none" />
      <path d="M146 210A110 110 0 1 1 185.3 294.3" stroke={`url(#pt-${id})`} strokeWidth="46" strokeLinecap="round" fill="none" />
      <path d="M340.3 280.7A110 110 0 0 1 185.3 294.3" stroke="#34D399" strokeWidth="46" strokeLinecap="round" fill="none" />
      <circle cx="185.3" cy="294.3" r="17" fill="#F7F7F5" />
    </svg>
  );
}
