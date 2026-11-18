import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { auth } from '@/firebase';
import { PinovaMark } from '@/components/layout/PinovaMark';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Eye, EyeOff, Loader2 } from 'lucide-react';
import { Toaster } from '@/components/ui/sonner';
import { toast } from 'sonner';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      await signInWithEmailAndPassword(auth, email, password);
      toast.success('Đăng nhập thành công.');
      navigate('/');
    } catch (error: any) {
      let errorMessage = 'Đăng nhập thất bại. Vui lòng kiểm tra lại kết nối.';
      
      switch (error.code) {
        case 'auth/invalid-credential':
        case 'auth/user-not-found':
        case 'auth/wrong-password':
          errorMessage = 'Email hoặc mật khẩu không chính xác.';
          break;
        case 'auth/invalid-email':
          errorMessage = 'Vui lòng nhập địa chỉ email hợp lệ.';
          break;
        case 'auth/too-many-requests':
          errorMessage = 'Thử quá nhiều lần. Vui lòng đợi một lát rồi thử lại.';
          break;
        default:
          errorMessage = 'Không thể đăng nhập vào hệ thống quản trị.';
      }
      
      toast.error(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <div className="login-bg relative flex min-h-screen items-center justify-center overflow-hidden p-4">
        {/* Static GPU-friendly radial atmosphere (zero continuous repaint) */}
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0"
          style={{
            background:
              'radial-gradient(640px circle at 15% 15%, rgba(16, 185, 129, 0.12), transparent 60%), radial-gradient(640px circle at 85% 85%, rgba(99, 102, 241, 0.12), transparent 60%)',
          }}
        />

        <div className="page-enter relative z-10 w-full max-w-md">
          <div className="mb-8 text-center">
            <div className="relative mx-auto mb-4 inline-flex h-16 w-16 shadow-[0_0_30px_rgba(16,185,129,0.25)] rounded-2xl">
              <PinovaMark tile className="h-16 w-16" />
            </div>
            <h1 className="text-2xl font-bold text-slate-50">Pinova Drive</h1>
            <p className="mt-2 text-sm text-slate-300">Vận hành hệ sinh thái pin &amp; Trợ lý Pinova AI</p>
          </div>

          <Card className="border-[var(--border-strong)] bg-[var(--bg-surface)]/90 shadow-2xl backdrop-blur-xl">
            <CardHeader className="pb-4 text-center">
              <CardTitle className="text-xl text-[var(--text-primary)]">Đăng nhập quản trị viên</CardTitle>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="space-y-2">
                  <label htmlFor="login-email" className="text-sm font-medium text-[var(--text-primary)]">Email</label>
                  <Input
                    id="login-email"
                    autoComplete="username"
                    type="email"
                    placeholder="admin@pinova.vn"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    className="min-h-12 border-[var(--border-hairline)] bg-[var(--bg-canvas)]/80"
                  />
                </div>

                <div className="space-y-2">
                  <label htmlFor="login-password" className="text-sm font-medium text-[var(--text-primary)]">Mật khẩu</label>
                  <div className="relative">
                    <Input
                      id="login-password"
                      autoComplete="current-password"
                      type={showPassword ? 'text' : 'password'}
                      placeholder="••••••••"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                      className="min-h-12 border-[var(--border-hairline)] bg-[var(--bg-canvas)]/80 pr-12"
                    />
                    <Button
                      type="button"
                      aria-label={showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
                      aria-pressed={showPassword}
                      variant="ghost"
                      size="icon"
                      className="absolute right-0 top-0 h-full min-h-12 min-w-12 px-3 text-[var(--text-muted)] hover:text-[var(--text-primary)]"
                      onClick={() => setShowPassword(!showPassword)}
                    >
                      {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                    </Button>
                  </div>
                </div>

                <Button
                  type="submit"
                  className="min-h-12 w-full bg-emerald-500 font-semibold text-slate-950 hover:bg-emerald-400"
                  disabled={loading}
                >
                  {loading ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Đang đăng nhập...
                    </>
                  ) : (
                    'Đăng nhập'
                  )}
                </Button>
              </form>
            </CardContent>
          </Card>

          <p className="mt-6 text-center text-xs text-[var(--text-secondary)]">
            Chỉ dành cho quản trị viên được ủy quyền. Mọi thao tác đều được ghi nhật ký.
          </p>
        </div>
      </div>
      <Toaster position="top-right" />
    </>
  );
}
