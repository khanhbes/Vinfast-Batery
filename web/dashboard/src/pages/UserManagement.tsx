import { useState, useEffect } from 'react';
import { Users, Plus, Search, Filter, MoreHorizontal, Mail, Calendar, Shield, Car, Edit, Trash2, UserIcon } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { User } from '@/types';
import { firebaseService, VehicleData } from '@/services/firebaseService';
import { getAuth } from 'firebase/auth';

const auth = getAuth();

interface ExtendedUser extends User {
  vehicleCount?: number;
  vehicles?: VehicleData[];
}

export default function UserManagement() {
  const [searchTerm, setSearchTerm] = useState('');
  const [users, setUsers] = useState<ExtendedUser[]>([]);
  const [vehicles, setVehicles] = useState<VehicleData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadUsersAndVehicles();
  }, []);

  const loadUsersAndVehicles = async () => {
    try {
      setLoading(true);
      
      // Get vehicles from Firebase
      const vehicleData = await firebaseService.getVehicles();
      setVehicles(vehicleData);

      // Create user list from vehicle owners
      const uniqueOwners = Array.from(
        new Map(
          vehicleData
            .filter(v => v.ownerUid)
            .map(v => [v.ownerUid!, {
              id: v.ownerUid!,
              email: `${v.ownerUid!.replace(/[^a-zA-Z0-9]/g, '').substring(0, 8)}@vinfast.com`,
              displayName: `User ${v.ownerUid!.replace(/[^a-zA-Z0-9]/g, '').substring(0, 6).toUpperCase()}`,
              role: 'user',
              createdAt: new Date().toISOString(),
              lastLogin: new Date().toISOString()
            }])
        ).values()
      );

      // Add current authenticated user as admin
      if (auth.currentUser) {
        const currentUser: ExtendedUser = {
          id: auth.currentUser.uid,
          email: auth.currentUser.email || 'admin@vinfast.com',
          displayName: auth.currentUser.displayName || 'Admin User',
          role: 'admin',
          createdAt: new Date().toISOString(),
          lastLogin: new Date().toISOString()
        };
        
        // Check if current user is already in the list
        const existingUserIndex = uniqueOwners.findIndex(u => u.id === currentUser.id);
        if (existingUserIndex >= 0) {
          uniqueOwners[existingUserIndex] = { ...uniqueOwners[existingUserIndex], role: 'admin' };
        } else {
          uniqueOwners.unshift(currentUser);
        }
      }

      // Count vehicles for each user
      const usersWithVehicleCount = uniqueOwners.map(user => {
        const userVehicles = vehicleData.filter(v => v.ownerUid === user.id);
        return {
          ...user,
          vehicleCount: userVehicles.length,
          vehicles: userVehicles
        };
      });

      setUsers(usersWithVehicleCount);
    } catch (error) {
      console.error('Error loading users:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredUsers = users.filter(user =>
    user.displayName.toLowerCase().includes(searchTerm.toLowerCase()) ||
    user.email.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const getRoleBadge = (role: string) => {
    switch (role) {
      case 'admin':
        return <Badge className="bg-purple-100 text-purple-800 hover:bg-purple-200">Quản trị viên</Badge>;
      case 'user':
        return <Badge className="bg-blue-100 text-blue-800 hover:bg-blue-200">Người dùng</Badge>;
      default:
        return <Badge variant="outline">{role}</Badge>;
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('vi-VN', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="w-8 h-8 border-4 border-primary/20 border-t-primary rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-muted-foreground">Đang tải dữ liệu người dùng...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-foreground">Quản lý người dùng</h1>
          <p className="text-muted-foreground mt-1">Quản lý tài khoản và phân quyền hệ thống</p>
        </div>
        <Button className="gap-2">
          <Plus className="w-4 h-4" />
          Thêm người dùng
        </Button>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-blue-100 rounded-lg">
                <Users className="w-6 h-6 text-blue-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{users.length}</p>
                <p className="text-sm text-muted-foreground">Tổng người dùng</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-purple-100 rounded-lg">
                <Shield className="w-6 h-6 text-purple-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">
                  {users.filter(u => u.role === 'admin').length}
                </p>
                <p className="text-sm text-muted-foreground">Quản trị viên</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-green-100 rounded-lg">
                <UserIcon className="w-6 h-6 text-green-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">
                  {users.filter(u => u.role === 'user').length}
                </p>
                <p className="text-sm text-muted-foreground">Người dùng thường</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
          <CardContent className="p-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-orange-100 rounded-lg">
                <Car className="w-6 h-6 text-orange-600" />
              </div>
              <div>
                <p className="text-2xl font-bold text-foreground">{vehicles.length}</p>
                <p className="text-sm text-muted-foreground">Tổng số xe</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Users Table */}
      <Card className="border-border/50 bg-surface/50 backdrop-blur-sm">
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="flex items-center gap-2">
              <Users className="w-5 h-5 text-primary" />
              Danh sách người dùng
            </CardTitle>
            <div className="flex items-center gap-2">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  placeholder="Tìm kiếm người dùng..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-10 bg-surface-light/50 border-border/50 w-64"
                />
              </div>
              <Button variant="outline" size="icon">
                <Filter className="w-4 h-4" />
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border/50">
                  <th className="text-left p-4 font-medium text-muted-foreground">Người dùng</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Email</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Vai trò</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Số xe</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Ngày tạo</th>
                  <th className="text-left p-4 font-medium text-muted-foreground">Đăng nhập cuối</th>
                  <th className="text-left p-4 font-medium text-muted-foreground text-center">Thao tác</th>
                </tr>
              </thead>
              <tbody>
                {filteredUsers.map((user) => (
                  <tr key={user.id} className="border-b border-border/30 hover:bg-surface-light/30 transition-colors">
                    <td className="p-4">
                      <div className="flex items-center gap-3">
                        <Avatar className="w-8 h-8">
                          <AvatarImage src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${user.email}`} />
                          <AvatarFallback>
                            {user.displayName.split(' ').map(n => n[0]).join('').toUpperCase()}
                          </AvatarFallback>
                        </Avatar>
                        <span className="font-medium text-foreground">{user.displayName}</span>
                      </div>
                    </td>
                    <td className="p-4 text-muted-foreground">{user.email}</td>
                    <td className="p-4">{getRoleBadge(user.role)}</td>
                    <td className="p-4">
                      <div className="flex items-center gap-1">
                        <Car className="w-4 h-4 text-muted-foreground" />
                        <span className="text-sm">{user.vehicleCount || 0}</span>
                      </div>
                    </td>
                    <td className="p-4 text-muted-foreground">{formatDate(user.createdAt)}</td>
                    <td className="p-4 text-muted-foreground">
                      {user.lastLogin ? formatDate(user.lastLogin) : 'Chưa đăng nhập'}
                    </td>
                    <td className="p-4">
                      <div className="flex items-center justify-center">
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon" className="text-muted-foreground hover:text-foreground">
                              <MoreHorizontal className="w-4 h-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end" className="bg-surface border-border">
                            <DropdownMenuItem className="hover:bg-surface-light cursor-pointer gap-2">
                              <Edit className="w-4 h-4" />
                              Chỉnh sửa
                            </DropdownMenuItem>
                            <DropdownMenuItem className="hover:bg-surface-light cursor-pointer gap-2">
                              <Shield className="w-4 h-4" />
                              Đổi vai trò
                            </DropdownMenuItem>
                            <DropdownMenuItem className="text-destructive hover:bg-destructive/10 cursor-pointer gap-2">
                              <Trash2 className="w-4 h-4" />
                              Xóa
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {filteredUsers.length === 0 && (
              <div className="text-center py-8">
                <Users className="w-8 h-8 text-muted-foreground mx-auto mb-2" />
                <p className="text-sm text-muted-foreground">Không tìm thấy người dùng nào</p>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
