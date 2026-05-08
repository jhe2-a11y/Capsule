import Foundation
import Supabase

/// Single shared Supabase client. Auth state is persisted by supabase-swift's
/// default keychain-backed session store.
enum SupabaseClientFactory {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )
}
