import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { auth } from '@/firebase';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { BatteryCharging, Eye, EyeOff, Loader2 } from 'lucide-react';
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
      toast.success('Signed in successfully.');
      navigate('/');
    } catch (error: any) {
      let errorMessage = 'Sign in failed';
      
      switch (error.code) {
        case 'auth/invalid-credential':
        case 'auth/user-not-found':
        case 'auth/wrong-password':
          errorMessage = 'Incorrect email address or password';
          break;
        case 'auth/invalid-email':
          errorMessage = 'Enter a valid email address';
          break;
        case 'auth/too-many-requests':
          errorMessage = 'Too many attempts. Please try again later';
          break;
        default:
          errorMessage = error.message || 'Sign in failed';
      }
      
      toast.error(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <div className="login-bg relative flex min-h-screen items-center justify-center overflow-hidden p-4">
        {/* Animated gradient orbs */}
        <div className="pointer-events-none absolute -left-40 -top-40 h-96 w-96 animate-[pulse_8s_ease-in-out_infinite] rounded-full bg-emerald-500/15 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-40 -right-40 h-96 w-96 animate-[pulse_10s_ease-in-out_infinite_2s] rounded-full bg-primary/10 blur-3xl" />

        <div className="page-enter relative z-10 w-full max-w-md">
          <div className="mb-8 text-center">
            <div className="relative mx-auto mb-4 inline-flex h-16 w-16 items-center justify-center rounded-2xl border border-emerald-500/20 bg-emerald-500/10 shadow-[0_0_30px_rgba(16,185,129,0.25)]">
              <BatteryCharging className="h-8 w-8 text-emerald-400" />
            </div>
            <h1 className="text-2xl font-bold text-foreground">VinFast BMS</h1>
            <p className="mt-2 text-sm text-muted-foreground">Battery operations and AI workspace</p>
          </div>

          <Card className="border-border/30 bg-card/80 shadow-2xl backdrop-blur-xl">
            <CardHeader className="pb-4 text-center">
              <CardTitle className="text-xl">Administrator sign in</CardTitle>
            </CardHeader>
            <CardContent>
              <form onSubmit={handleSubmit} className="space-y-4">
                <div className="space-y-2">
                  <label htmlFor="login-email" className="text-sm font-medium text-foreground">Email</label>
                  <Input
                    id="login-email"
                    autoComplete="username"
                    type="email"
                    placeholder="you@example.com"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    className="border-border/40 bg-background/60"
                  />
                </div>

                <div className="space-y-2">
                  <label htmlFor="login-password" className="text-sm font-medium text-foreground">Password</label>
                  <div className="relative">
                    <Input
                      id="login-password"
                      autoComplete="current-password"
                      type={showPassword ? 'text' : 'password'}
                      placeholder="••••••••"
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      required
                      className="border-border/40 bg-background/60 pr-10"
                    />
                    <Button
                      type="button"
                      aria-label={showPassword ? 'Hide password' : 'Show password'}
                      aria-pressed={showPassword}
                      variant="ghost"
                      size="icon"
                      className="absolute right-0 top-0 h-full px-3 text-muted-foreground hover:text-foreground"
                      onClick={() => setShowPassword(!showPassword)}
                    >
                      {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                    </Button>
                  </div>
                </div>

                <Button
                  type="submit"
                  className="w-full bg-emerald-500 text-slate-950 hover:bg-emerald-400"
                  disabled={loading}
                >
                  {loading ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Signing in...
                    </>
                  ) : (
                    'Sign in'
                  )}
                </Button>
              </form>
            </CardContent>
          </Card>

          <p className="mt-6 text-center text-xs text-muted-foreground/60">
            Authorized administrators only. Activity is logged.
          </p>
        </div>
      </div>
      <Toaster position="top-right" />
    </>
  );
}
