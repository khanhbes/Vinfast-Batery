import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, User, Mail, Phone, Calendar, ShieldCheck, Check, Edit2 } from 'lucide-react';
import { UserProfile } from '../types';

interface ProfileModalProps {
  isOpen: boolean;
  onClose: () => void;
  profile: UserProfile;
  onSaveProfile: (updated: UserProfile) => void;
  vehiclesCount: number;
}

export const ProfileModal: React.FC<ProfileModalProps> = ({
  isOpen,
  onClose,
  profile,
  onSaveProfile,
  vehiclesCount,
}) => {
  const [name, setName] = useState(profile.name);
  const [email, setEmail] = useState(profile.email);
  const [phone, setPhone] = useState(profile.phone || '0988 123 456');
  const [isEditing, setIsEditing] = useState(false);
  const [showSavedToast, setShowSavedToast] = useState(false);

  const handleSave = () => {
    onSaveProfile({
      ...profile,
      name,
      email,
      phone,
    });
    setIsEditing(false);
    setShowSavedToast(true);
    setTimeout(() => setShowSavedToast(false), 2000);
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
            className="relative w-full max-w-md bg-[#0c0c0c] border border-white/10 rounded-3xl p-5 md:p-6 shadow-2xl z-10 max-h-[90vh] overflow-y-auto"
          >
            {/* Header */}
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <h3 className="text-base font-bold text-white">Hồ sơ người dùng</h3>
              <button
                type="button"
                onClick={onClose}
                className="w-8 h-8 rounded-full bg-white/5 text-slate-400 hover:text-white flex items-center justify-center border border-white/5"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Profile Avatar Card */}
            <div className="mt-4 text-center">
              <div className="w-20 h-20 rounded-3xl bg-gradient-to-tr from-blue-600 via-sky-500 to-emerald-400 text-white font-black text-2xl flex items-center justify-center mx-auto shadow-xl shadow-sky-500/20 border-2 border-white/10">
                {profile.avatarText}
              </div>
              <h2 className="text-lg font-bold text-white mt-3">{profile.name}</h2>
              <p className="text-xs text-slate-400 font-mono">{profile.email}</p>
              <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs font-semibold mt-2">
                <ShieldCheck className="w-3.5 h-3.5" />
                Tài khoản đã xác minh
              </div>
            </div>

            {/* Stats Row */}
            <div className="grid grid-cols-2 gap-2 mt-4 text-center">
              <div className="p-3 rounded-2xl bg-white/5 border border-white/5">
                <span className="text-[10px] text-slate-400 block uppercase font-medium">Garage xe</span>
                <span className="text-sm font-bold text-white">{vehiclesCount} phương tiện</span>
              </div>
              <div className="p-3 rounded-2xl bg-white/5 border border-white/5">
                <span className="text-[10px] text-slate-400 block uppercase font-medium">Thành viên từ</span>
                <span className="text-sm font-bold text-white">{profile.joinedDate || '10/2024'}</span>
              </div>
            </div>

            {/* Form Fields */}
            <div className="mt-4 space-y-3">
              <div>
                <label className="text-xs text-slate-400 block mb-1">Họ và tên</label>
                <div className="relative">
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    disabled={!isEditing}
                    className="w-full bg-[#111] border border-white/10 rounded-2xl px-3.5 py-2.5 text-xs text-white disabled:opacity-75 focus:outline-none focus:border-emerald-500"
                  />
                  <User className="w-4 h-4 text-slate-500 absolute right-3.5 top-3" />
                </div>
              </div>

              <div>
                <label className="text-xs text-slate-400 block mb-1">Email đăng nhập</label>
                <div className="relative">
                  <input
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    disabled={!isEditing}
                    className="w-full bg-[#111] border border-white/10 rounded-2xl px-3.5 py-2.5 text-xs text-white disabled:opacity-75 focus:outline-none focus:border-emerald-500"
                  />
                  <Mail className="w-4 h-4 text-slate-500 absolute right-3.5 top-3" />
                </div>
              </div>

              <div>
                <label className="text-xs text-slate-400 block mb-1">Số điện thoại</label>
                <div className="relative">
                  <input
                    type="text"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    disabled={!isEditing}
                    className="w-full bg-[#111] border border-white/10 rounded-2xl px-3.5 py-2.5 text-xs text-white disabled:opacity-75 focus:outline-none focus:border-emerald-500"
                  />
                  <Phone className="w-4 h-4 text-slate-500 absolute right-3.5 top-3" />
                </div>
              </div>
            </div>

            {showSavedToast && (
              <div className="mt-3 p-2.5 bg-emerald-500/10 border border-emerald-500/30 rounded-2xl text-xs text-emerald-300 text-center flex items-center justify-center gap-1.5">
                <Check className="w-3.5 h-3.5" />
                Đã cập nhật thông tin thành công!
              </div>
            )}

            {/* Actions */}
            <div className="mt-5 flex gap-2">
              {!isEditing ? (
                <button
                  type="button"
                  onClick={() => setIsEditing(true)}
                  className="w-full py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-white font-semibold text-xs border border-white/10 flex items-center justify-center gap-1.5 transition-colors"
                >
                  <Edit2 className="w-3.5 h-3.5 text-emerald-400" />
                  Chỉnh sửa hồ sơ
                </button>
              ) : (
                <>
                  <button
                    type="button"
                    onClick={() => setIsEditing(false)}
                    className="flex-1 py-3 rounded-2xl bg-white/5 hover:bg-white/10 text-slate-300 font-semibold text-xs border border-white/5"
                  >
                    Hủy
                  </button>
                  <button
                    type="button"
                    onClick={handleSave}
                    className="flex-1 py-3 rounded-2xl bg-emerald-500 hover:bg-emerald-400 text-slate-950 font-bold text-xs shadow-lg shadow-emerald-500/20"
                  >
                    Lưu thay đổi
                  </button>
                </>
              )}
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};
