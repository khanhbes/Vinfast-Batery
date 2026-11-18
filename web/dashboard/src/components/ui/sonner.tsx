import { Toaster as Sonner } from "sonner"

type ToasterProps = React.ComponentProps<typeof Sonner>

const Toaster = ({ ...props }: ToasterProps) => {
  return (
    <Sonner
      theme="dark"
      richColors
      className="toaster group"
      toastOptions={{
        classNames: {
          toast:
            "group toast !rounded-xl !border !border-[var(--border-strong)] !bg-[var(--bg-elevated)] !text-[var(--text-primary)] !shadow-2xl",
          description: "!text-[var(--text-secondary)]",
          actionButton:
            "!bg-[var(--accent-primary)] !text-white hover:!bg-[var(--accent-hover)]",
          cancelButton:
            "!bg-[var(--bg-surface)] !text-[var(--text-secondary)]",
          closeButton:
            "!border-[var(--border-strong)] !bg-[var(--bg-surface)] !text-[var(--text-secondary)] hover:!text-[var(--text-primary)]",
        },
      }}
      {...props}
    />
  )
}

export { Toaster }
