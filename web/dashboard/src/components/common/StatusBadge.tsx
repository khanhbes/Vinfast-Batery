import React from 'react';

export type BadgeTone = 'success' | 'warning' | 'danger' | 'info' | 'neutral' | 'primary';

export interface StatusBadgeProps {
  label: string;
  tone?: BadgeTone;
  dot?: boolean;
  className?: string;
  title?: string;
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({
  label,
  tone = 'neutral',
  dot = true,
  className = '',
  title,
}) => {
  const toneStyles: Record<BadgeTone, string> = {
    success:
      'bg-[var(--status-success-bg)] text-[var(--status-success-fg)] border-[var(--status-success-border)]',
    warning:
      'bg-[var(--status-warning-bg)] text-[var(--status-warning-fg)] border-[var(--status-warning-border)]',
    danger:
      'bg-[var(--status-danger-bg)] text-[var(--status-danger-fg)] border-[var(--status-danger-border)]',
    info: 'bg-[var(--status-info-bg)] text-[var(--status-info-fg)] border-[var(--status-info-border)]',
    primary:
      'bg-[var(--accent-tint)] text-[var(--accent-primary)] border-[var(--accent-border)]',
    neutral:
      'bg-slate-500/10 text-[var(--text-secondary)] border-[var(--border-hairline)]',
  };

  const dotColors: Record<BadgeTone, string> = {
    success: 'bg-[var(--status-success-dot)]',
    warning: 'bg-[var(--status-warning-dot)]',
    danger: 'bg-[var(--status-danger-dot)]',
    info: 'bg-[var(--status-info-dot)]',
    primary: 'bg-[var(--accent-primary)]',
    neutral: 'bg-slate-400',
  };

  return (
    <span
      title={title}
      className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-xs font-medium border whitespace-nowrap shrink-0 leading-4 ${toneStyles[tone]} ${className}`}
    >
      {dot && <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${dotColors[tone]}`} />}
      <span>{label}</span>
    </span>
  );
};

export const PlanBadge: React.FC<{
  planIdOrName?: string;
  planId?: string;
  planName?: string;
}> = ({ planIdOrName, planId, planName }) => {
  const key = (planIdOrName || planName || planId || '').toLowerCase();
  if (key.includes('enterprise') || key.includes('fleet') || key.includes('doanh nghiệp')) {
    return <StatusBadge label="Doanh nghiệp" tone="primary" dot={false} />;
  }
  if (key.includes('ultra')) {
    return <StatusBadge label="Pinova Ultra" tone="primary" dot={false} />;
  }
  if (key.includes('pro')) {
    return <StatusBadge label="Pinova Pro" tone="info" dot={false} />;
  }
  if (key.includes('plus')) {
    return <StatusBadge label="Pinova Plus" tone="success" dot={false} />;
  }
  return <StatusBadge label="Miễn phí" tone="neutral" dot={false} />;
};
