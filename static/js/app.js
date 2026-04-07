/**
 * VinFast Battery - Enhanced App with Charts & Analytics
 */
let currentVehicleId = null, vehicles = [], chargeLogs = [];
let miniChart = null, lineChart = null, distChart = null, durChart = null;

// ============================================================
// INIT
// ============================================================
document.addEventListener('DOMContentLoaded', async () => {
  await loadVehicles();
  setupTimeListeners();
});

// ============================================================
// VEHICLES
// ============================================================
async function loadVehicles() {
  try {
    const res = await fetch('/api/vehicles');
    const j = await res.json();
    if (j.success) { vehicles = j.data; renderVehicleSelector(); if (vehicles.length) selectVehicle(vehicles[0].vehicleId); }
  } catch(e) { showToast('Lỗi tải xe','error'); }
}

function renderVehicleSelector() {
  document.getElementById('vehicleSelector').innerHTML = vehicles.map(v => `
    <div class="vehicle-chip ${v.vehicleId===currentVehicleId?'active':''}" onclick="selectVehicle('${v.vehicleId}')">
      <div class="vehicle-chip-dot" style="background:${v.avatarColor||'#00C853'}"></div>
      <div><div class="vehicle-chip-name">${v.vehicleName}</div><div class="vehicle-chip-odo">ODO: ${v.currentOdo.toLocaleString()} km</div></div>
    </div>`).join('');
}

async function selectVehicle(id) {
  currentVehicleId = id;
  renderVehicleSelector();
  await Promise.all([loadStats(), loadLogs()]);
  updateHero();
  renderCharts();
}

// ============================================================
// HERO & GAUGE
// ============================================================
function updateHero() {
  const v = vehicles.find(x=>x.vehicleId===currentVehicleId);
  if (!v) return;
  document.getElementById('heroName').textContent = v.vehicleName;
  document.getElementById('heroId').textContent = v.vehicleId;
  document.getElementById('heroOdo').textContent = v.currentOdo.toLocaleString();
  // Last charge percent
  const last = chargeLogs[0];
  const pct = last ? last.endBatteryPercent : 0;
  document.getElementById('gaugePercent').textContent = pct + '%';
  // Animate gauge
  const fill = document.getElementById('gaugeFill');
  const circumference = 2 * Math.PI * 52;
  const offset = circumference - (pct / 100) * circumference;
  fill.style.strokeDashoffset = offset;
  fill.style.stroke = pct > 60 ? '#00C853' : pct > 30 ? '#FFB300' : '#E53935';
  // Hero stats
  document.getElementById('heroCharges').textContent = v.totalCharges || chargeLogs.length;
  const avgGain = chargeLogs.length ? Math.round(chargeLogs.reduce((s,l)=>s+l.endBatteryPercent-l.startBatteryPercent,0)/chargeLogs.length) : 0;
  document.getElementById('heroAvgGain').textContent = avgGain;
}

// ============================================================
// STATS
// ============================================================
async function loadStats() {
  try {
    const res = await fetch(`/api/stats/${currentVehicleId}`);
    const j = await res.json();
    if (j.success) {
      const d = j.data;
      animateValue('statTotal',d.totalCharges);
      animateValue('statAvgGain',d.avgChargeGain,'%');
      animateValue('statTotalGain',d.totalEnergyGained,'%');
      animateValue('statAvgTime',d.avgChargeDuration,'h');
    }
  } catch(e){}
}

function animateValue(id,target,unit='') {
  const el = document.getElementById(id);
  const dur = 800, start = performance.now();
  function upd(now) {
    const p = Math.min((now-start)/dur,1);
    const e = 1-Math.pow(1-p,3);
    const c = Math.round((target*e)*10)/10;
    el.innerHTML = `${c}${unit?`<span class="stat-unit">${unit}</span>`:''}`;
    if (p<1) requestAnimationFrame(upd);
  }
  requestAnimationFrame(upd);
}

// ============================================================
// LOGS
// ============================================================
async function loadLogs() {
  try {
    const res = await fetch(`/api/charge-logs?vehicleId=${currentVehicleId}`);
    const j = await res.json();
    if (j.success) { chargeLogs = j.data; renderLogs(); renderRecentLogs(); document.getElementById('logCount').textContent = chargeLogs.length; }
  } catch(e) { showToast('Lỗi tải nhật ký','error'); }
}

function renderLogs() {
  const el = document.getElementById('logsGrid');
  if (!chargeLogs.length) { el.innerHTML = '<div class="empty-state"><div class="icon">🔋</div><p>Chưa có nhật ký sạc</p></div>'; return; }
  el.innerHTML = chargeLogs.map(l => {
    const st=new Date(l.startTime),et=new Date(l.endTime),dur=et-st;
    const h=Math.floor(dur/36e5),m=Math.floor((dur%36e5)/6e4);
    const gain=l.endBatteryPercent-l.startBatteryPercent;
    const ds=st.toLocaleDateString('vi-VN',{day:'2-digit',month:'2-digit',year:'numeric'});
    const ts=`${st.toLocaleTimeString('vi-VN',{hour:'2-digit',minute:'2-digit'})} → ${et.toLocaleTimeString('vi-VN',{hour:'2-digit',minute:'2-digit'})}`;
    return `<div class="log-card"><div class="log-card-top"><div><div class="log-field-value">${ds}</div><div class="log-date">${ts} · ${h}h${String(m).padStart(2,'0')}m</div></div><button class="btn btn-danger btn-sm" onclick="deleteLog('${l.logId}')">🗑️ Xóa</button></div><div class="log-card-body"><div><div class="log-field-label">Pin trước</div><div class="log-field-value" style="color:var(--danger-light)">${l.startBatteryPercent}%</div></div><div><div class="log-field-label">Pin sau</div><div class="log-field-value" style="color:var(--accent)">${l.endBatteryPercent}%</div></div><div><div class="log-field-label">Đã nạp</div><div class="log-field-value" style="color:var(--info)">+${gain}%</div></div><div><div class="log-field-label">ODO</div><div class="log-field-value">${l.odoAtCharge.toLocaleString()} km</div></div></div><div class="battery-bar-wrap"><div class="battery-bar-bg"><div class="battery-bar-fill" style="width:${l.endBatteryPercent}%"></div></div><div class="battery-labels"><span>${l.startBatteryPercent}%</span><span>${l.endBatteryPercent}%</span></div></div></div>`;
  }).join('');
}

function renderRecentLogs() {
  const el = document.getElementById('recentLogs');
  const recent = chargeLogs.slice(0,5);
  if (!recent.length) { el.innerHTML = '<div class="empty-state"><p>Chưa có dữ liệu</p></div>'; return; }
  el.innerHTML = recent.map(l => {
    const d = new Date(l.startTime);
    const ds = d.toLocaleDateString('vi-VN',{day:'2-digit',month:'2-digit'});
    const gain = l.endBatteryPercent - l.startBatteryPercent;
    return `<div class="recent-log"><div class="recent-log-icon up">⚡</div><div class="recent-log-info"><div class="recent-log-title">${ds} · ${l.startBatteryPercent}% → ${l.endBatteryPercent}%</div><div class="recent-log-sub">ODO: ${l.odoAtCharge.toLocaleString()} km</div></div><div class="recent-log-badge">+${gain}%</div></div>`;
  }).join('');
}

async function deleteLog(id) {
  if (!confirm('Xóa nhật ký này?')) return;
  try {
    const res = await fetch(`/api/charge-logs/${id}`,{method:'DELETE'});
    const j = await res.json();
    if (j.success) { showToast('Đã xóa','success'); await loadVehicles(); selectVehicle(currentVehicleId); }
    else showToast(j.error,'error');
  } catch(e) { showToast('Lỗi','error'); }
}

// ============================================================
// CHARTS
// ============================================================
function renderCharts() {
  if (!chargeLogs.length) return;
  const sorted = [...chargeLogs].reverse();
  const labels = sorted.map(l => { const d=new Date(l.startTime); return d.toLocaleDateString('vi-VN',{day:'2-digit',month:'2-digit'}); });
  const startData = sorted.map(l=>l.startBatteryPercent);
  const endData = sorted.map(l=>l.endBatteryPercent);
  const gainData = sorted.map(l=>l.endBatteryPercent-l.startBatteryPercent);
  const durData = sorted.map(l=> { const d=new Date(l.endTime)-new Date(l.startTime); return Math.round(d/36e5*10)/10; });

  const chartOpts = { responsive:true, maintainAspectRatio:false, plugins:{legend:{labels:{color:'#B0B0CC',font:{family:'Inter',size:11}}}}, scales:{x:{ticks:{color:'#6A6A8A',font:{size:10}},grid:{color:'rgba(46,46,78,.5)'}},y:{ticks:{color:'#6A6A8A',font:{size:10}},grid:{color:'rgba(46,46,78,.3)'}}} };

  // Mini chart (dashboard)
  if (miniChart) miniChart.destroy();
  const mc = document.getElementById('miniChart');
  if (mc) {
    miniChart = new Chart(mc, { type:'line', data:{ labels, datasets:[
      {label:'Pin trước',data:startData,borderColor:'#FF6B6B',backgroundColor:'rgba(255,107,107,.1)',fill:true,tension:.4,pointRadius:3,pointBackgroundColor:'#FF6B6B',borderWidth:2},
      {label:'Pin sau',data:endData,borderColor:'#00C853',backgroundColor:'rgba(0,200,83,.1)',fill:true,tension:.4,pointRadius:3,pointBackgroundColor:'#00C853',borderWidth:2}
    ]}, options:{...chartOpts,plugins:{...chartOpts.plugins,legend:{position:'top',labels:{color:'#B0B0CC',font:{family:'Inter',size:11},usePointStyle:true,pointStyle:'circle'}}}} });
  }

  // Line chart (analytics)
  if (lineChart) lineChart.destroy();
  const lc = document.getElementById('batteryLineChart');
  if (lc) {
    lineChart = new Chart(lc, { type:'line', data:{ labels, datasets:[
      {label:'Trước sạc (%)',data:startData,borderColor:'#FF6B6B',backgroundColor:'rgba(255,107,107,.08)',fill:true,tension:.4,pointRadius:4,pointHoverRadius:6,borderWidth:2},
      {label:'Sau sạc (%)',data:endData,borderColor:'#00C853',backgroundColor:'rgba(0,200,83,.08)',fill:true,tension:.4,pointRadius:4,pointHoverRadius:6,borderWidth:2},
      {label:'Đã nạp (%)',data:gainData,borderColor:'#448AFF',borderDash:[5,5],tension:.4,pointRadius:3,borderWidth:2}
    ]}, options:chartOpts });
  }

  // Distribution bar chart
  if (distChart) distChart.destroy();
  const dc = document.getElementById('chargeDistChart');
  if (dc) {
    distChart = new Chart(dc, { type:'bar', data:{ labels, datasets:[
      {label:'Mức nạp (%)',data:gainData,backgroundColor:gainData.map(g=>g>70?'rgba(0,200,83,.7)':g>40?'rgba(255,179,0,.7)':'rgba(255,107,107,.7)'),borderRadius:6,borderSkipped:false}
    ]}, options:{...chartOpts,plugins:{...chartOpts.plugins,legend:{display:false}}} });
  }

  // Duration chart
  if (durChart) durChart.destroy();
  const drc = document.getElementById('durationChart');
  if (drc) {
    durChart = new Chart(drc, { type:'bar', data:{ labels, datasets:[
      {label:'Giờ sạc',data:durData,backgroundColor:'rgba(124,77,255,.6)',borderRadius:6,borderSkipped:false}
    ]}, options:{...chartOpts,plugins:{...chartOpts.plugins,legend:{display:false}},scales:{...chartOpts.scales,y:{...chartOpts.scales.y,title:{display:true,text:'Giờ',color:'#6A6A8A'}}}} });
  }
}

// ============================================================
// TABS & SIDEBAR
// ============================================================
function switchTab(tab) {
  document.querySelectorAll('.tab-content').forEach(t=>t.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n=>n.classList.remove('active'));
  document.getElementById('tab-'+tab).classList.add('active');
  document.querySelector(`.nav-item[data-tab="${tab}"]`).classList.add('active');
  if (tab==='analytics') setTimeout(()=>renderCharts(),100);
}

function toggleSidebar() {
  document.getElementById('sidebar').classList.toggle('open');
}

// ============================================================
// MODAL
// ============================================================
function openModal() {
  document.getElementById('modalOverlay').classList.add('active');
  document.body.style.overflow='hidden';
  const v=vehicles.find(x=>x.vehicleId===currentVehicleId);
  if(v){
    document.getElementById('modalVehicleInfo').innerHTML=`<div class="vehicle-info-icon">🏍️</div><div class="vehicle-info-text"><div class="name">${v.vehicleName} (${v.vehicleId})</div><div class="odo">ODO hiện tại: ${v.currentOdo.toLocaleString()} km</div></div>`;
    document.getElementById('odoInput').placeholder=`Tối thiểu: ${v.currentOdo} km`;
  }
  clearErrors();
}
function closeModal(){document.getElementById('modalOverlay').classList.remove('active');document.body.style.overflow=''}
function handleOverlayClick(e){if(e.target===e.currentTarget)closeModal()}

// ============================================================
// TIME
// ============================================================
function setupTimeListeners(){
  document.getElementById('startTime').addEventListener('change',updateDuration);
  document.getElementById('endTime').addEventListener('change',updateDuration);
}
function updateDuration(){
  const s=document.getElementById('startTime').value,e=document.getElementById('endTime').value,card=document.getElementById('durationCard');
  if(!s||!e){card.innerHTML='';return}
  const d=new Date(e)-new Date(s);
  if(d<=0){card.innerHTML='<div class="duration-card invalid">⚠️ Thời gian không hợp lệ</div>';return}
  const h=Math.floor(d/36e5),m=Math.floor((d%36e5)/6e4);
  card.innerHTML=`<div class="duration-card valid">⏱️ Thời gian sạc: ${h}h ${String(m).padStart(2,'0')}m</div>`;
}

// ============================================================
// FORM
// ============================================================
function clearErrors(){document.querySelectorAll('.form-error').forEach(e=>e.textContent='');document.querySelectorAll('.form-control.error').forEach(e=>e.classList.remove('error'))}
function setError(fid,eid,msg){const f=document.getElementById(fid),e=document.getElementById(eid);if(f)f.classList.add('error');if(e)e.textContent=msg}

async function handleSubmit(e) {
  e.preventDefault(); clearErrors();
  const sb=document.getElementById('startBattery').value.trim(),eb=document.getElementById('endBattery').value.trim(),odo=document.getElementById('odoInput').value.trim(),st=document.getElementById('startTime').value,et=document.getElementById('endTime').value;
  const v=vehicles.find(x=>x.vehicleId===currentVehicleId);
  let err=false;
  if(!sb){setError('startBattery','errStartBattery','Không được để trống');err=true}else if(+sb<0||+sb>100){setError('startBattery','errStartBattery','0-100');err=true}
  if(!eb){setError('endBattery','errEndBattery','Không được để trống');err=true}else if(+eb<0||+eb>100){setError('endBattery','errEndBattery','0-100');err=true}
  if(sb&&eb&&+eb<=+sb){setError('endBattery','errEndBattery',`Phải > ${sb}%`);err=true}
  if(!odo){setError('odoInput','errOdo','Không được để trống');err=true}else if(v&&+odo<v.currentOdo){setError('odoInput','errOdo',`Phải ≥ ${v.currentOdo} km`);err=true}
  if(!st){setError('startTime','errStartTime','Chọn thời gian');err=true}
  if(!et){setError('endTime','errEndTime','Chọn thời gian');err=true}
  if(st&&et&&new Date(et)<=new Date(st)){setError('endTime','errEndTime','Phải sau bắt đầu');err=true}
  if(err)return;

  const btn=document.getElementById('submitBtn'),txt=document.getElementById('submitText'),spin=document.getElementById('submitSpinner');
  btn.disabled=true;txt.style.display='none';spin.style.display='block';
  try{
    const res=await fetch('/api/charge-logs',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({vehicleId:currentVehicleId,startBatteryPercent:+sb,endBatteryPercent:+eb,odoAtCharge:+odo,startTime:new Date(st).toISOString(),endTime:new Date(et).toISOString()})});
    const j=await res.json();
    if(j.success){showToast('✅ '+(j.message||'Đã lưu!'),'success');closeModal();document.getElementById('chargeForm').reset();document.getElementById('endBattery').value='100';document.getElementById('durationCard').innerHTML='';await loadVehicles();selectVehicle(currentVehicleId)}
    else showToast('❌ '+j.error,'error');
  }catch(err){showToast('❌ Lỗi kết nối','error')}
  finally{btn.disabled=false;txt.style.display='';spin.style.display='none'}
}

// ============================================================
// TOAST
// ============================================================
function showToast(msg,type='success'){
  const c=document.getElementById('toastContainer'),t=document.createElement('div');
  t.className=`toast ${type}`;t.textContent=msg;c.appendChild(t);setTimeout(()=>t.remove(),3200);
}
