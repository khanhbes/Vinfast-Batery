import { useId } from 'react';

/** Pinova mark (QA 133, the owner's artwork): a "P" made of the app's charge
 * dial — platinum ring on a stem, an emerald charge track set into the ring,
 * a white knob on a dark gap. Geometry in 1024 units (app/brand/pinova_mark.svg). */
export function PinovaMark({ className, tile = false }: { className?: string; tile?: boolean }) {
  const id = useId().replace(/:/g, '');
  return (
    <svg viewBox="0 0 1024 1024" className={className} role="img" aria-label="Pinova">
      {tile && (
        <>
          <defs>
            <radialGradient id={`bg-${id}`} cx="50%" cy="40%" r="75%">
              <stop offset="0" stopColor="#1A1C1F" />
              <stop offset="1" stopColor="#050506" />
            </radialGradient>
          </defs>
          <rect width="1024" height="1024" rx="230" fill={`url(#bg-${id})`} />
        </>
      )}
      <g fill="none" stroke="#D6D8DB" strokeWidth="75" strokeLinecap="round">
        <path d="M332 422.5V780" />
        <path d="M332 422.5A180 180 0 1 1 401.2 564.3" />
      </g>
      <circle cx="401.2" cy="564.3" r="46.5" fill="#050506" />
      <circle cx="401.2" cy="564.3" r="37.5" fill="#D6D8DB" />
      <path d="M653.8 533.3A180 180 0 0 1 401.2 564.3" fill="none" stroke="#34D399" strokeWidth="58" strokeLinecap="round" />
      <circle cx="401.2" cy="564.3" r="18.5" fill="#FFFFFF" />
    </svg>
  );
}
