import { Bell, Search, ChevronDown } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';

export function Topbar() {
  return (
    <header className="h-16 border-b border-border bg-background sticky top-0 z-40 px-8 flex items-center justify-between">
      <div className="flex items-center gap-4 flex-1 max-w-md">
        <div className="relative w-full">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <Input 
            placeholder="Tìm kiếm người dùng, xe, mã lỗi..." 
            className="pl-10 bg-surface border-border focus-visible:ring-primary text-sm"
          />
        </div>
      </div>

      <div className="flex items-center gap-6">
        <div className="relative">
          <Button variant="ghost" size="icon" className="relative text-muted-foreground hover:text-primary hover:bg-surface-light">
            <Bell className="w-5 h-5" />
            <span className="absolute top-2 right-2 w-2 h-2 bg-primary rounded-full border-2 border-background shadow-[0_0_8px_rgba(0,209,255,0.5)]" />
          </Button>
        </div>

        <div className="h-8 w-[1px] bg-border" />

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" className="flex items-center gap-3 px-2 hover:bg-surface-light">
              <Avatar className="w-8 h-8 border border-border">
                <AvatarImage src="https://api.dicebear.com/7.x/avataaars/svg?seed=Admin" />
                <AvatarFallback>AD</AvatarFallback>
              </Avatar>
              <div className="text-left hidden md:block">
                <p className="text-sm font-semibold text-foreground leading-none">Admin Khanh</p>
                <p className="text-[10px] text-muted-foreground mt-1 uppercase tracking-wider">Quản trị viên</p>
              </div>
              <ChevronDown className="w-4 h-4 text-muted-foreground" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56 bg-surface border-border text-foreground">
            <DropdownMenuLabel className="text-muted-foreground text-[10px] uppercase tracking-widest">Tài khoản của tôi</DropdownMenuLabel>
            <DropdownMenuSeparator className="bg-border" />
            <DropdownMenuItem className="hover:bg-surface-light cursor-pointer">Hồ sơ cá nhân</DropdownMenuItem>
            <DropdownMenuItem className="hover:bg-surface-light cursor-pointer">Cài đặt bảo mật</DropdownMenuItem>
            <DropdownMenuSeparator className="bg-border" />
            <DropdownMenuItem className="text-destructive hover:bg-destructive/10 cursor-pointer font-medium">Đăng xuất</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
