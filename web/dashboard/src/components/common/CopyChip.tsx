import React, { useState } from 'react';
import { Check, Copy, Eye, EyeOff } from 'lucide-react';

export function truncateMiddle(str: string, frontLen = 8, backLen = 4): string {
  if (!str) return '';
  if (str.length <= frontLen + backLen) return str;
  return `${str.slice(0, frontLen)}…${str.slice(-backLen)}`;
}

export const CopyChip: React.FC<{
  value: string;
  head?: number;
  tail?: number;
  className?: string;
  onCopyAudit?: () => void;
}> = ({ value, head = 8, tail = 4, className = '', onCopyAudit }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = (e: React.MouseEvent) => {
    e.stopPropagation();
    void navigator.clipboard?.writeText(value);
    setCopied(true);
    if (onCopyAudit) onCopyAudit();
    setTimeout(() => setCopied(false), 1600);
  };

  return (
    <button
      type="button"
      onClick={handleCopy}
      title={`${value} — Nhấn để sao chép`}
      className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] hover:border-[var(--border-strong)] border border-[var(--border-hairline)] text-xs font-mono text-[var(--text-secondary)] hover:text-[var(--text-primary)] whitespace-nowrap transition-colors btn-press ${className}`}
    >
      <span>{truncateMiddle(value, head, tail)}</span>
      {copied ? (
        <Check className="w-3 h-3 text-emerald-400 shrink-0" />
      ) : (
        <Copy className="w-3 h-3 opacity-60 shrink-0" />
      )}
    </button>
  );
};

export const SecretField: React.FC<{
  value: string;
  revealed: boolean;
  onToggleReveal: () => void;
  onCopy?: () => void;
  className?: string;
}> = ({ value, revealed, onToggleReveal, onCopy, className = '' }) => {
  const [copied, setCopied] = useState(false);

  return (
    <div className={`inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-[var(--bg-elevated)] border border-[var(--border-hairline)] text-xs font-mono ${className}`}>
      <span className="select-all text-[var(--text-primary)]">
        {revealed ? value : '••••••••••••••••••••••••'}
      </span>
      <button
        type="button"
        onClick={onToggleReveal}
        title={revealed ? 'Ẩn khóa bí mật' : 'Hiện khóa bí mật'}
        aria-label={revealed ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
        className="p-1 rounded hover:bg-slate-500/10 text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
      >
        {revealed ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
      </button>
      {onCopy && (
        <button
          type="button"
          onClick={() => {
            void navigator.clipboard?.writeText(value);
            setCopied(true);
            onCopy();
            setTimeout(() => setCopied(false), 1600);
          }}
          title="Sao chép khóa"
          aria-label="Sao chép mật khẩu"
          className="p-1 rounded hover:bg-slate-500/10 text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
        >
          {copied ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
        </button>
      )}
    </div>
  );
};
