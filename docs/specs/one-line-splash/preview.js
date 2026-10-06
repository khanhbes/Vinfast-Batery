const preview=document.querySelector('#preview'),scrub=document.querySelector('#scrub'),reduced=document.querySelector('#reduced');
let running=false,last=0,elapsed=0,raf=0;
reduced.checked=matchMedia('(prefers-reduced-motion: reduce)').matches;
function show(ms){elapsed=ms;scrub.value=ms;document.querySelector('#time').textContent=(ms/1000).toFixed(2)+' s';OneLine.mount(preview,ms,reduced.checked);}
function stop(){running=false;cancelAnimationFrame(raf);}
function tick(now){if(!running)return;elapsed+=now-last;last=now;show(Math.min(elapsed,reduced.checked?1000:4500));if(elapsed<(reduced.checked?1000:4500))raf=requestAnimationFrame(tick);else stop();}
document.querySelector('#play').onclick=()=>{stop();show(0);running=true;last=performance.now();raf=requestAnimationFrame(tick);};
document.querySelector('#pause').onclick=stop;
scrub.oninput=()=>{stop();show(Number(scrub.value));};reduced.onchange=()=>{stop();show(0);};
let resume=false;document.addEventListener('visibilitychange',()=>{if(document.hidden){resume=running;stop();}else if(resume){resume=false;running=true;last=performance.now();raf=requestAnimationFrame(tick);}});
function download(host,name){const svg=host.querySelector('svg').cloneNode(true);svg.setAttribute('width','780');svg.setAttribute('height','1688');const url=URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(svg)],{type:'image/svg+xml'}));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
document.querySelector('#export').onclick=()=>download(preview,`one-line-${Math.round(elapsed)}ms.svg`);
OneLine.frames.forEach((ms,i)=>{const figure=document.createElement('figure'),host=document.createElement('div'),caption=document.createElement('figcaption'),button=document.createElement('button');OneLine.mount(host,ms);caption.textContent=`0${i+1} / ${(ms/1000).toFixed(2)}s · ${OneLine.titles[i]}`;button.textContent='Tải SVG 780 × 1688';button.onclick=()=>download(host,`one-line-frame-${i+1}-${ms}ms.svg`);figure.append(host,caption,button);document.querySelector('#frames').append(figure);});
show(0);
