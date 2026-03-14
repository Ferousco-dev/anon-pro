import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<bool> isMaintenanceEnabled() async {
    try {
      final res = await _client
          .from('app_settings')
          .select('maintenance_mode')
          .eq('id', 1)
          .maybeSingle();
      if (res != null) {
        return res['maintenance_mode'] == true;
      }

      final fallback = await _client
          .from('app_settings')
          .select('maintenance_mode')
          .limit(1)
          .maybeSingle();
      return fallback != null && fallback['maintenance_mode'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isUserAdmin(String userId) async {
    try {
      final res = await _client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      return res != null && res['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  Future<bool> shouldBlockAuthenticated(User user) async {
    final maintenance = await isMaintenanceEnabled();
    if (!maintenance) return false;
    final isAdmin = await isUserAdmin(user.id);
    return !isAdmin;
  }
}
