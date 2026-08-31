import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, User, Mail, Phone, Lock, Smartphone, LogOut, Check, ChevronRight } from 'lucide-react';
import { UserProfile } from '../types';

interface AccountSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  profile: UserProfile;
  onUpdateProfile: (profile: UserProfile) => void;
  onOpenLogout: () => void;
}

export const AccountSettingsModal: React.FC<AccountSettingsModalProps> = ({
  isOpen,
  onClose,
  profile,
  onUpdateProfile,
  onOpenLogout,
}) => {
  const [name, setName] = useState(profile.name);
  const [phone, setPhone] = useState(profile.phone || '0988 123 456');
  const [isEditing, setIsEditing] = useState(false);
  const [isSaved, setIsSaved] = useState(false);

  const handleSave = () => {
    onUpdateProfile({
      ...profile,
      name,
      phone,
      avatarText: name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase() || 'EV',
    });
    setIsSaved(true);
    setIsEditing(false);
    setTimeout(() => setIsSaved(false), 2000);
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/80 backdrop-blur-md"
          />

          <motion.div
            initial={{ scale: 0.95, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.95, opacity: 0 }}
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[88vh] overflow-y-auto"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-2xl bg-emerald-500/20 text-emerald-400 border border-emerald-500/30 flex items-center justify-center">
                  <User className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="text-base font-bold text-white">Tài khoản của tôi</h3>
                  <p className="text-[11px] text-slate-400">Thông tin cá nhân & bảo mật tài khoản</p>
                </div>
              </div>
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Avatar Header */}
            <div className="mt-4 p-4 rounded-2xl bg-[#111] border border-white/5 flex items-center gap-4">
              <div className="w-14 h-14 rounded-2xl bg-gradient-to-tr from-[#19528d] to-[#4fa3e3] text-white font-black text-lg flex items-center justify-center shadow-lg shadow-sky-900/30 border border-white/10 shrink-0">
                {profile.avatarText}
              </div>
              <div className="flex-1 min-w-0">
                <h4 className="font-bold text-white text-base truncate">{profile.name}</h4>
                <p className="text-xs text-slate-400 font-mono truncate">{profile.email}</p>
                <span className="inline-block mt-1 text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-medium">
                  Tài khoản cá nhân đã xác thực
                </span>
              </div>
            </div>

            {/* Form Fields */}
            <div className="mt-4 space-y-3">
              <div className="space-y-1">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Tên hiển thị
                </label>
                <div className="relative">
                  <input
                    type="text"
                    value={name}
                    disabled={!isEditing}
                    onChange={(e) => setName(e.target.value)}
                    className="w-full bg-[#111] border border-white/10 rounded-2xl px-4 py-2.5 text-sm text-white focus:outline-none focus:border-emerald-500 disabled:opacity-80 disabled:cursor-not-allowed"
                  />
                </div>
              </div>

              <div className="space-y-1">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Email
                </label>
                <div className="relative">
                  <input
                    type="email"
                    value={profile.email}
                    disabled
                    className="w-full bg-[#111] border border-white/5 rounded-2xl px-4 py-2.5 text-sm font-mono text-slate-400 cursor-not-allowed"
                  />
                  <span className="absolute right-3 top-2.5 text-[10px] text-slate-500">
                    Cố định
                  </span>
                </div>
              </div>

              <div className="space-y-1">
                <label className="text-[11px] font-bold text-slate-400 uppercase tracking-wider px-1">
                  Số điện thoại
                </label>
                <input
                  type="tel"
                  value={phone}
                  disabled={!isEditing}
                  onChange={(e) => setPhone(e.target.value)}
                  className="w-full bg-[#111] border border-white/10 rounded-2xl px-4 py-2.5 text-sm font-mono text-white focus:outline-none focus:border-emerald-500 disabled:opacity-80 disabled:cursor-not-allowed"
                />
              </div>

              {/* Disabled & Dimmed Items as per Spec */}
              <div className="pt-2 space-y-2">
                {/* Đổi mật khẩu */}
                <div className="p-3.5 rounded-2xl bg-white/[0.02] border border-white/5 flex items-center justify-between opacity-50 cursor-not-allowed">
                  <div className="flex items-center gap-3">
                    <Lock className="w-4 h-4 text-slate-500" />
                    <div>
                      <div className="text-xs font-bold text-slate-400">Đổi mật khẩu</div>
                      <div className="text-[10px] text-slate-500">Đăng nhập bằng Google OAuth</div>
                    </div>
                  </div>
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/5 text-slate-500 border border-white/5">
                    Đang phát triển
                  </span>
                </div>

                {/* Thiết bị đang đăng nhập */}
                <div className="p-3.5 rounded-2xl bg-white/[0.02] border border-white/5 flex items-center justify-between opacity-50 cursor-not-allowed">
                  <div className="flex items-center gap-3">
                    <Smartphone className="w-4 h-4 text-slate-500" />
                    <div>
                      <div className="text-xs font-bold text-slate-400">Thiết bị đang đăng nhập</div>
                      <div className="text-[10px] text-slate-500">Quản lý phiên đăng nhập đa thiết bị</div>
                    </div>
                  </div>
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-white/5 text-slate-500 border border-white/5">
                    Đang phát triển
                  </span>
                </div>
              </div>
            </div>

            {/* Actions */}
            <div className="mt-5 space-y-2">
              {isEditing ? (
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => {
                      setName(profile.name);
                      setPhone(profile.phone || '0988 123 456');
                      setIsEditing(false);
                    }}
                    className="flex-1 py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 font-semibold text-xs border border-white/5"
                  >
                    Hủy
                  </button>
                  <button
                    type="button"
                    onClick={handleSave}
                    className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-1.5"
                  >
                    <Check className="w-4 h-4 stroke-[3]" />
                    Lưu thông tin
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => setIsEditing(true)}
                  className="w-full py-3 rounded-2xl bg-white/10 hover:bg-white/15 text-white font-bold text-xs border border-white/10"
                >
                  Chỉnh sửa thông tin
                </button>
              )}

              {isSaved && (
                <div className="p-2 text-center text-xs text-emerald-400 font-medium">
                  Đã cập nhật thông tin thành công!
                </div>
              )}

              <button
                type="button"
                onClick={() => {
                  onClose();
                  onOpenLogout();
                }}
                className="w-full py-3 rounded-2xl bg-red-500/10 hover:bg-red-500/20 text-red-400 font-bold text-xs border border-red-500/20 flex items-center justify-center gap-2"
              >
                <LogOut className="w-3.5 h-3.5" />
                Đăng xuất
              </button>
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
