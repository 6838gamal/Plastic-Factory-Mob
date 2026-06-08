import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/api_datasource.dart';

class AppUser {
  final String id;
  final String email;
  const AppUser({required this.id, required this.email});
}

class AuthState {
  final AppUser? user;
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
    AppUser? user,
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
      final user = AppUser(
        id: userMap['id'] as String,
        email: userMap['email'] as String,
      );
      state = state.copyWith(user: user, isAdmin: true, isLoading: false);
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
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
