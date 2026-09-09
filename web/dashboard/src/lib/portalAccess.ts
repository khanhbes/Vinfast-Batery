export function isVerifiedAdmin(response: unknown, uid: string): boolean {
  if (!response || typeof response !== 'object') return false;
  const value = response as { success?: unknown; data?: { uid?: unknown; role?: unknown } };
  return value.success === true && value.data?.uid === uid && value.data?.role === 'admin';
}
