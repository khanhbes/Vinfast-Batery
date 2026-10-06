/* Design prototype only. No app routes, credentials, network, or device control. */
const OneLine = (() => {
  const path = 'M 135 344 L 157 344 L 195 405 L 233 344 L 255 344 L 205 425 Q 195 441 185 425 Z';
  const frames = [0, 400, 1100, 1850, 2450, 3000, 3950, 4500];
  const titles = ['Native · nền thuần', 'Spark · điểm sáng', 'Line · 120 px', 'Draw · đầu bút', 'Fill · khép nét', 'Reveal · quét sáng', 'Brand · giữ tĩnh', 'Gate · sẵn sàng chuyển'];
  const clamp = x => Math.min(1, Math.max(0, x));
  function bezier(x, a, b, c, d) {
    let lo=0, hi=1, t=x;
    const f=(t,p,q)=>3*(1-t)*(1-t)*t*p+3*(1-t)*t*t*q+t*t*t;
    for(let i=0;i<20;i++){t=(lo+hi)/2; if(f(t,a,c)<x)lo=t;else hi=t;}
    return f(t,b,d);
  }
  function phase(t,a,b,kind='out') { const x=clamp((t-a)/(b-a)); return x===0||x===1?x:kind==='inout'?bezier(x,.65,0,.35,1):bezier(x,.22,1,.36,1); }
  function svg(ms, reduced=false) {
    const t=clamp(ms/4500)*4500;
    const draw=reduced?1:phase(t,1250,2250,'inout');
    const fill=reduced?phase(t,0,1000):phase(t,2350,2650);
    const name=reduced?fill:phase(t,3350,3650);
    const tag=reduced?fill:phase(t,3470,3770);
    const sweep=phase(t,2800,3250,'inout');
    const pathOpacity=reduced?fill:(t>=1250?1:0);
    const atmosphere=reduced?fill:phase(t,0,500);
    const lineWidth=120*phase(t,600,1100);
    const lineAlpha=!reduced&&t<1250?phase(t,0,400):0;
    const headOpacity=!reduced&&t>=1250&&t<2250?1:0;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 390 844" width="390" height="844" role="img" aria-label="VinFast Battery, đang khởi động">
      <defs>
        <radialGradient id="bg"><stop stop-color="#111A17"/><stop offset="1" stop-color="#0B0F0E"/></radialGradient>
        <linearGradient id="fill" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#3DDC97"/><stop offset="1" stop-color="#2BB673"/></linearGradient>
        <linearGradient id="light"><stop stop-color="#FFF6E5" stop-opacity="0"/><stop offset=".5" stop-color="#FFF6E5" stop-opacity=".45"/><stop offset="1" stop-color="#FFF6E5" stop-opacity="0"/></linearGradient>
        <linearGradient id="taper"><stop stop-color="#C8F7E2" stop-opacity="0"/><stop offset=".2" stop-color="#C8F7E2"/><stop offset=".8" stop-color="#C8F7E2"/><stop offset="1" stop-color="#C8F7E2" stop-opacity="0"/></linearGradient>
        <filter id="halo" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>
        <clipPath id="logo"><path d="${path}"/></clipPath>
      </defs>
      <rect width="390" height="844" fill="#0B0F0E"/>
      <rect width="390" height="844" fill="url(#bg)" opacity="${atmosphere}"/>
      <g opacity="${lineAlpha}">
        <path d="M ${195-lineWidth/2} 344 H ${195+lineWidth/2}" stroke="#3DDC97" stroke-width="8" opacity=".14" filter="url(#halo)"/>
        <path d="M ${195-lineWidth/2} 344 H ${195+lineWidth/2}" stroke="url(#taper)" stroke-width="1.8"/>
        <circle cx="195" cy="344" r="1.5" fill="#C8F7E2" opacity="${1-phase(t,600,1100)}"/>
      </g>
      <g opacity="${pathOpacity}">
        <path d="${path}" fill="url(#fill)" fill-opacity="${fill}" stroke="none"/>
        <path data-metric="true" d="${path}" pathLength="1" fill="none" stroke="#3DDC97" stroke-opacity=".55" stroke-width="1.5" stroke-linejoin="round" stroke-dasharray="${draw} 1"/>
        <path data-trail="true" d="${path}" fill="none" stroke="#C8F7E2" stroke-width="1.8" opacity="${headOpacity}"/>
        <circle data-halo="true" r="7" fill="#3DDC97" filter="url(#halo)" opacity="${headOpacity*.14}"/>
        <circle data-head="true" r="1.6" fill="#C8F7E2" opacity="${headOpacity}"/>
        <g clip-path="url(#logo)"><rect x="${95+210*sweep}" y="310" width="40" height="170" transform="rotate(20 195 390)" fill="url(#light)" opacity="${!reduced&&t>=2800&&t<=3250?1:0}"/></g>
        <path d="M135 344 H157 L195 405" stroke="#C8F7E2" stroke-width=".8" fill="none" opacity="${!reduced&&t>=2800&&t<=3250?.3*Math.sin(Math.PI*sweep):0}"/>
      </g>
      <text x="195" y="${486+8*(1-name)}" text-anchor="middle" fill="#F3F0E9" font-family="Inter, Arial, sans-serif" font-size="28" font-weight="600" letter-spacing="2.24" opacity="${name}">VinFast Battery</text>
      <text x="195" y="519" text-anchor="middle" fill="#A9B4AD" font-family="Inter, Arial, sans-serif" font-size="14" opacity="${tag}">Hiểu pin. Sạc thông minh.</text>
    </svg>`;
  }
  function mount(host,ms,reduced=false) {
    host.innerHTML=svg(ms,reduced);
    const p=host.querySelector('[data-metric]'), length=p.getTotalLength();
    const draw=reduced?1:phase(ms,1250,2250,'inout'), end=length*draw;
    const point=p.getPointAtLength(end);
    for(const selector of ['[data-head]','[data-halo]']) {
      const el=host.querySelector(selector); el.setAttribute('cx',point.x);el.setAttribute('cy',point.y);
    }
    const trail=host.querySelector('[data-trail]');
    trail.setAttribute('stroke-dasharray',`${Math.min(28,end)} ${length}`);
    trail.setAttribute('stroke-dashoffset',String(-Math.max(0,end-28)));
  }
  return {svg,mount,frames,titles,path};
})();
if(typeof module!=='undefined')module.exports=OneLine;
