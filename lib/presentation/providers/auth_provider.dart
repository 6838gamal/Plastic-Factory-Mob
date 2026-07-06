import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';

class AppUser {
  final String id;
  final String email;
  final String role;
  final String? name;
  const AppUser({
    required this.id,
    required this.email,
    this.role = 'admin',
    this.name,
  });
}

class AuthState {
  final AppUser? user;
  final bool isAdmin;
  final bool isWarehouseManager;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.isAdmin = false,
    this.isWarehouseManager = false,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    AppUser? user,
    bool? isAdmin,
    bool? isWarehouseManager,
    bool? isLoading,
    String? error,
  }) =>
      AuthState(
        user: user ?? this.user,
        isAdmin: isAdmin ?? this.isAdmin,
        isWarehouseManager: isWarehouseManager ?? this.isWarehouseManager,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

final dataSourceProvider = Provider<ApiDataSource>((ref) => ApiDataSource());

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final ds = ref.read(dataSourceProvider);
      final response = await ds.signIn(email, password);
      final userMap = response['user'] as Map<String, dynamic>;
      final role = userMap['role'] as String? ?? 'admin';
      final name = userMap['name'] as String?;
      final user = AppUser(
        id: userMap['id'] as String,
        email: userMap['email'] as String,
        role: role,
        name: name,
      );
      state = state.copyWith(
        user: user,
        isAdmin: role == 'admin',
        isWarehouseManager: role == 'warehouse_manager',
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'خطأ في تسجيل الدخول: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    final ds = ref.read(dataSourceProvider);
    await ds.signOut();
    state = const AuthState();
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    final userId = state.user?.id;
    if (userId == null) return false;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final ds = ref.read(dataSourceProvider);
      await ds.changePassword(userId, currentPassword, newPassword);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> changeEmail(String currentPassword, String newEmail) async {
    final userId = state.user?.id;
    if (userId == null) return false;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final ds = ref.read(dataSourceProvider);
      final res = await ds.changeEmail(userId, currentPassword, newEmail);
      final userMap = res['user'] as Map<String, dynamic>;
      final user = AppUser(
        id: userMap['id'] as String,
        email: userMap['email'] as String,
        role: state.user?.role ?? 'admin',
        name: state.user?.name,
      );
      state = state.copyWith(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
