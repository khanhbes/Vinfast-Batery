import React, { useState } from 'react';
import { 
  User, Car, Zap, Sparkles, BatteryCharging, 
  Bell, Database, Shield, Palette, Globe, 
  HelpCircle, Info, ChevronRight, LogOut, Code,
  Check
} from 'lucide-react';
import { AppSettings, Vehicle, UserProfile, ChargingSession } from '../types';
import { AccountSettingsModal } from './AccountSettingsModal';
import { VehicleSettingsModal } from './VehicleSettingsModal';
import { ChargerSettingsModal } from './ChargerSettingsModal';
import { PersonalAiSettingsModal } from './PersonalAiSettingsModal';
import { SmartChargePreferencesModal } from './SmartChargePreferencesModal';
import { NotificationSettingsModal } from './NotificationSettingsModal';
import { DataSettingsModal } from './DataSettingsModal';
import { PrivacySettingsModal } from './PrivacySettingsModal';
import { AppearanceSettingsModal } from './AppearanceSettingsModal';
import { LanguageUnitSettingsModal } from './LanguageUnitSettingsModal';
import { HelpSupportModal } from './HelpSupportModal';
import { AboutAppModal } from './AboutAppModal';
import { DeveloperSettingsModal } from './DeveloperSettingsModal';
import { LogoutModal } from './LogoutModal';

interface SettingsTabProps {
  settings: AppSettings;
  vehicles: Vehicle[];
  activeVehicleId: string;
  sessions: ChargingSession[];
  profile: UserProfile;
  onUpdateProfile: (profile: UserProfile) => void;
  onSelectVehicle: (id: string) => void;
  onArchiveVehicle: (id: string) => void;
  onRestoreVehicle: (id: string) => void;
  onOpenGarage: () => void;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
  onNavigateToHistory: () => void;
  onClearAllChargingData?: () => void;
  onRestoreSession?: (id: string) => void;
}

export const SettingsTab: React.FC<SettingsTabProps> = ({
  settings,
  vehicles,
  activeVehicleId,
  sessions,
  profile,
  onUpdateProfile,
  onSelectVehicle,
  onArchiveVehicle,
  onRestoreVehicle,
  onOpenGarage,
  onUpdateSettings,
  onNavigateToHistory,
  onClearAllChargingData,
  onRestoreSession,
}) => {
  // Modal states
  const [isAccountOpen, setIsAccountOpen] = useState(false);
  const [isVehicleSettingsOpen, setIsVehicleSettingsOpen] = useState(false);
  const [isChargerSettingsOpen, setIsChargerSettingsOpen] = useState(false);
  const [isPersonalAiOpen, setIsPersonalAiOpen] = useState(false);
  const [isSmartChargePrefsOpen, setIsSmartChargePrefsOpen] = useState(false);
  const [isNotificationSettingsOpen, setIsNotificationSettingsOpen] = useState(false);
  const [isDataSettingsOpen, setIsDataSettingsOpen] = useState(false);
  const [isPrivacySettingsOpen, setIsPrivacySettingsOpen] = useState(false);
  const [isAppearanceOpen, setIsAppearanceOpen] = useState(false);
  const [isLanguageUnitOpen, setIsLanguageUnitOpen] = useState(false);
  const [isHelpSupportOpen, setIsHelpSupportOpen] = useState(false);
  const [isAboutAppOpen, setIsAboutAppOpen] = useState(false);
  const [isDeveloperModeOpen, setIsDeveloperModeOpen] = useState(false);
  const [isLogoutOpen, setIsLogoutOpen] = useState(false);

  const activeVehicle = vehicles.find(v => v.id === activeVehicleId) || vehicles[0];

  const handleUnlockDeveloperMode = () => {
    onUpdateSettings({ developerModeUnlocked: true });
  };

  const handleLockDeveloperMode = () => {
    onUpdateSettings({ developerModeUnlocked: false });
  };

  const getThemeSummary = (theme: string) => {
    switch (theme) {
      case 'dark': return 'Tối Obsidian';
      case 'amoled': return 'Pure AMOLED';
      case 'light': return 'Sáng';
      default: return 'Theo hệ thống';
    }
  };

  return (
    <div id="settings-view" className="space-y-6 pb-28 pt-1 animate-fadeIn max-w-lg mx-auto">
      {/* Header */}
      <div className="px-1">
        <h1 className="text-2xl font-extrabold text-white tracking-tight">
          Cài đặt
        </h1>
        <p className="text-xs text-slate-400 mt-1">
          Cấu hình phương tiện, AI cá nhân và tùy chọn ứng dụng
        </p>
      </div>

      {/* Profile Card Header */}
      <button
        type="button"
        onClick={() => setIsAccountOpen(true)}
        className="w-full bg-[#111] hover:bg-[#151515] border border-white/5 rounded-3xl p-4 flex items-center justify-between transition-all group shadow-xl active:scale-[0.99] text-left"
      >
        <div className="flex items-center gap-3.5">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-[#19528d] to-[#4fa3e3] text-white font-black text-base flex items-center justify-center shadow-lg shadow-sky-900/30 border border-white/10 shrink-0">
            {profile.avatarText}
          </div>
          <div className="min-w-0">
            <h2 className="font-bold text-white text-base group-hover:text-emerald-400 transition-colors truncate">
              {profile.name}
            </h2>
            <p className="text-xs text-slate-400 font-mono truncate">{profile.email}</p>
          </div>
        </div>
        <ChevronRight className="w-5 h-5 text-slate-500 group-hover:text-white transition-colors shrink-0" />
      </button>

      {/* GROUP 1: XE */}
      <div className="space-y-2">
        <div className="px-2 text-[11px] font-bold text-slate-500 uppercase tracking-widest">
          Xe
        </div>

        <div className="bg-[#111] border border-white/5 rounded-3xl overflow-hidden divide-y divide-white/5">
          {/* Xe của tôi */}
          <button
            type="button"
            onClick={() => setIsVehicleSettingsOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Car className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Xe của tôi
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  {activeVehicle ? `${activeVehicle.name} • Pin 68%` : 'Chưa chọn xe'}
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>

          {/* Bộ sạc & kết nối */}
          <button
            type="button"
            onClick={() => setIsChargerSettingsOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Zap className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Bộ sạc & kết nối
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5 flex items-center gap-1.5">
                  <span>{activeVehicle?.chargerBinding?.chargerName || 'Chưa kết nối'}</span>
                  {activeVehicle?.chargerBinding?.isConnected && (
                    <span className="text-emerald-400 font-medium">• Đã kết nối</span>
                  )}
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>
        </div>
      </div>

      {/* GROUP 2: AI & SẠC */}
      <div className="space-y-2">
        <div className="px-2 text-[11px] font-bold text-slate-500 uppercase tracking-widest">
          AI & Sạc
        </div>

        <div className="bg-[#111] border border-white/5 rounded-3xl overflow-hidden divide-y divide-white/5">
          {/* AI cá nhân */}
          <button
            type="button"
            onClick={() => setIsPersonalAiOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Sparkles className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  AI cá nhân
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  {activeVehicle?.personalAiEnabled ? 'Đã cá nhân hóa cho xe này' : 'Tạm dừng'}
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>

          {/* Sạc thông minh */}
          <button
            type="button"
            onClick={() => setIsSmartChargePrefsOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <BatteryCharging className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Sạc thông minh
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  Mức pin mặc định {settings.defaultTargetPercent || 80}% • Tự ngắt an toàn
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>
        </div>
      </div>

      {/* GROUP 3: THÔNG BÁO */}
      <div className="space-y-2">
        <div className="px-2 text-[11px] font-bold text-slate-500 uppercase tracking-widest">
          Thông báo
        </div>

        <div className="bg-[#111] border border-white/5 rounded-3xl overflow-hidden">
          <button
            type="button"
            onClick={() => setIsNotificationSettingsOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Bell className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Thông báo
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  Sạc hoàn tất, ngắt khẩn cấp & cảnh báo pin
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>
        </div>
      </div>

      {/* GROUP 4: DỮ LIỆU & QUYỀN RIÊNG TƯ */}
      <div className="space-y-2">
        <div className="px-2 text-[11px] font-bold text-slate-500 uppercase tracking-widest">
          Dữ liệu & Quyền riêng tư
        </div>

        <div className="bg-[#111] border border-white/5 rounded-3xl overflow-hidden divide-y divide-white/5">
          {/* Lịch sử & dữ liệu */}
          <button
            type="button"
            onClick={() => setIsDataSettingsOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Database className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Lịch sử & dữ liệu
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  {sessions.length} phiên sạc • Xuất dữ liệu JSON
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>

          {/* Quyền riêng tư & bảo mật */}
          <button
            type="button"
            onClick={() => setIsPrivacySettingsOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Shield className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Quyền riêng tư & bảo mật
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  Dữ liệu AI cô lập • Mã hóa cục bộ
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>
        </div>
      </div>

      {/* GROUP 5: ỨNG DỤNG */}
      <div className="space-y-2">
        <div className="px-2 text-[11px] font-bold text-slate-500 uppercase tracking-widest">
          Ứng dụng
        </div>

        <div className="bg-[#111] border border-white/5 rounded-3xl overflow-hidden divide-y divide-white/5">
          {/* Giao diện */}
          <button
            type="button"
            onClick={() => setIsAppearanceOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Palette className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Giao diện
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  {getThemeSummary(settings.theme)} • Rung xúc giác
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>

          {/* Ngôn ngữ & đơn vị */}
          <button
            type="button"
            onClick={() => setIsLanguageUnitOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Globe className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Ngôn ngữ & đơn vị
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  {settings.language === 'en' ? 'English' : 'Tiếng Việt'} • Tự động Wh/kWh
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>
        </div>
      </div>

      {/* GROUP 6: HỖ TRỢ */}
      <div className="space-y-2">
        <div className="px-2 text-[11px] font-bold text-slate-500 uppercase tracking-widest">
          Hỗ trợ
        </div>

        <div className="bg-[#111] border border-white/5 rounded-3xl overflow-hidden divide-y divide-white/5">
          {/* Hướng dẫn & trợ giúp */}
          <button
            type="button"
            onClick={() => setIsHelpSupportOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <HelpCircle className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Hướng dẫn & trợ giúp
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  Câu hỏi thường gặp & Gửi báo cáo lỗi
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>

          {/* Thông tin ứng dụng */}
          <button
            type="button"
            onClick={() => setIsAboutAppOpen(true)}
            className="w-full p-4 flex items-center justify-between text-left hover:bg-white/[0.02] transition-colors group"
          >
            <div className="flex items-center gap-3.5">
              <div className="w-9 h-9 rounded-2xl bg-white/5 text-slate-300 flex items-center justify-center group-hover:text-emerald-400 transition-colors">
                <Info className="w-4 h-4" />
              </div>
              <div>
                <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                  Thông tin ứng dụng
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5 font-mono">
                  Phiên bản 1.4.0 (Build PROD)
                </div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-slate-500 group-hover:text-white transition-colors" />
          </button>
        </div>
      </div>

      {/* GROUP 7: DEVELOPER (Chỉ hiển thị khi đã mở khóa bằng 7-tap) */}
      {settings.developerModeUnlocked && (
        <div className="space-y-2 animate-fadeIn">
          <div className="px-2 text-[11px] font-bold text-emerald-400 uppercase tracking-widest flex items-center gap-1.5 font-mono">
            <Code className="w-3.5 h-3.5" />
            <span>Developer Mode</span>
          </div>

          <div className="bg-[#0c140e] border border-emerald-500/30 rounded-3xl overflow-hidden shadow-lg shadow-emerald-950/40">
            <button
              type="button"
              onClick={() => setIsDeveloperModeOpen(true)}
              className="w-full p-4 flex items-center justify-between text-left hover:bg-emerald-500/10 transition-colors group"
            >
              <div className="flex items-center gap-3.5">
                <div className="w-9 h-9 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <Code className="w-4 h-4" />
                </div>
                <div>
                  <div className="text-xs font-bold text-white group-hover:text-emerald-400 transition-colors">
                    Tùy chọn nhà phát triển
                  </div>
                  <div className="text-[11px] text-emerald-400/80 mt-0.5 font-mono">
                    Telemetry, AI Fusion & Shelly RPC
                  </div>
                </div>
              </div>
              <ChevronRight className="w-4 h-4 text-emerald-400 group-hover:text-white transition-colors" />
            </button>
          </div>
        </div>
      )}

      {/* Đăng xuất button */}
      <div className="pt-2">
        <button
          type="button"
          onClick={() => setIsLogoutOpen(true)}
          className="w-full py-4 rounded-3xl bg-red-500/10 hover:bg-red-500/20 text-red-400 font-bold text-xs border border-red-500/20 flex items-center justify-center gap-2 transition-all active:scale-[0.99]"
        >
          <LogOut className="w-4 h-4" />
          <span>Đăng xuất tài khoản</span>
        </button>
      </div>

      {/* MODALS RENDER */}
      <AccountSettingsModal
        isOpen={isAccountOpen}
        onClose={() => setIsAccountOpen(false)}
        profile={profile}
        onUpdateProfile={onUpdateProfile}
        onOpenLogout={() => setIsLogoutOpen(true)}
      />

      <VehicleSettingsModal
        isOpen={isVehicleSettingsOpen}
        onClose={() => setIsVehicleSettingsOpen(false)}
        vehicles={vehicles}
        activeVehicleId={activeVehicleId}
        onSelectVehicle={onSelectVehicle}
        onArchiveVehicle={onArchiveVehicle}
        onRestoreVehicle={onRestoreVehicle}
        onOpenGarage={onOpenGarage}
      />

      <ChargerSettingsModal
        isOpen={isChargerSettingsOpen}
        onClose={() => setIsChargerSettingsOpen(false)}
        vehicles={vehicles}
      />

      <PersonalAiSettingsModal
        isOpen={isPersonalAiOpen}
        onClose={() => setIsPersonalAiOpen(false)}
        vehicles={vehicles}
      />

      <SmartChargePreferencesModal
        isOpen={isSmartChargePrefsOpen}
        onClose={() => setIsSmartChargePrefsOpen(false)}
        settings={settings}
        onUpdateSettings={onUpdateSettings}
      />

      <NotificationSettingsModal
        isOpen={isNotificationSettingsOpen}
        onClose={() => setIsNotificationSettingsOpen(false)}
        settings={settings}
        onUpdateSettings={onUpdateSettings}
      />

      <DataSettingsModal
        isOpen={isDataSettingsOpen}
        onClose={() => setIsDataSettingsOpen(false)}
        sessions={sessions}
        onNavigateToHistory={onNavigateToHistory}
        onRestoreSession={onRestoreSession}
        allowDataForAi={settings.allowDataForAi ?? true}
        onToggleAllowDataForAi={(enabled) => onUpdateSettings({ allowDataForAi: enabled })}
      />

      <PrivacySettingsModal
        isOpen={isPrivacySettingsOpen}
        onClose={() => setIsPrivacySettingsOpen(false)}
        onClearAllChargingData={onClearAllChargingData}
      />

      <AppearanceSettingsModal
        isOpen={isAppearanceOpen}
        onClose={() => setIsAppearanceOpen(false)}
        settings={settings}
        onUpdateSettings={onUpdateSettings}
      />

      <LanguageUnitSettingsModal
        isOpen={isLanguageUnitOpen}
        onClose={() => setIsLanguageUnitOpen(false)}
        settings={settings}
        onUpdateSettings={onUpdateSettings}
      />

      <HelpSupportModal
        isOpen={isHelpSupportOpen}
        onClose={() => setIsHelpSupportOpen(false)}
      />

      <AboutAppModal
        isOpen={isAboutAppOpen}
        onClose={() => setIsAboutAppOpen(false)}
        developerModeUnlocked={settings.developerModeUnlocked ?? false}
        onUnlockDeveloperMode={handleUnlockDeveloperMode}
      />

      <DeveloperSettingsModal
        isOpen={isDeveloperModeOpen}
        onClose={() => setIsDeveloperModeOpen(false)}
        onLockDeveloperMode={handleLockDeveloperMode}
      />

      <LogoutModal
        isOpen={isLogoutOpen}
        onClose={() => setIsLogoutOpen(false)}
        onConfirmLogout={() => {
          setIsLogoutOpen(false);
        }}
      />
    </div>
  );
};
