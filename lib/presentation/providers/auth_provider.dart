import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/datasources/supabase_datasource.dart';
import '../../data/supabase/supabase_config.dart';

class AuthState {
  final User? user;
  final bool isAdmin;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.isAdmin = false,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    User? user,
    bool? isAdmin,
    bool? isLoading,
    String? error,
  }) =>
      AuthState(
        user: user ?? this.user,
        isAdmin: isAdmin ?? this.isAdmin,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

final dataSourceProvider = Provider<SupabaseDataSource>((ref) => SupabaseDataSource());

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    if (!SupabaseConfig.isConfigured) {
      return const AuthState();
    }
    try {
      final ds = ref.read(dataSourceProvider);
      final currentUser = ds.currentUser;
      return AuthState(
        user: currentUser,
        isAdmin: currentUser != null,
      );
    } catch (_) {
      return const AuthState();
    }
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final ds = ref.read(dataSourceProvider);
      final response = await ds.signIn(email, password);
      if (response.user != null) {
        state = state.copyWith(
          user: response.user,
          isAdmin: true,
          isLoading: false,
        );
        return true;
      }
      state = state.copyWith(isLoading: false, error: 'بيانات خاطئة');
      return false;
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
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
