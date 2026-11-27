package com.syahifilms.sphere.ui

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument

@Composable
fun SphereNav() {
    val nav = rememberNavController()
    val optional = { name: String -> navArgument(name) { type = NavType.StringType; nullable = true; defaultValue = null } }
    NavHost(navController = nav, startDestination = "splash") {
        composable("splash") { SplashScreen(nav) }
        composable("welcome") { WelcomeScreen(nav) }
        composable("login") { LoginScreen(nav) }
        composable("signup") { SignupScreen(nav) }
        composable("chooseRole") { ChooseRoleScreen(nav) }
        composable("otpLogin") { NativeOtpScreen(nav) }
        composable("verifyPhone") { NativePhoneVerifyScreen(nav) }
        composable("suspended") { NativeSuspendedScreen(nav) }
        composable("editorDetails") { NativeAccountGate(nav) { EditorDetailsScreen(nav) } }
        composable("verification") { NativeAccountGate(nav) { VerificationScreen(nav) } }
        composable("home") { NativeAccountGate(nav) { HomeScreen(nav) } }
        composable("saved") { NativeAccountGate(nav) { SavedEditorsScreen(nav) } }
        composable("verifiedPc") { NativeAccountGate(nav) { VerifiedPcScreen(nav) } }
        composable("vault") { NativeAccountGate(nav) { VaultNativeScreen(nav) } }
        composable("payments") { NativeAccountGate(nav) { NativePaymentsScreen(nav) } }
        if (com.syahifilms.sphere.BuildConfig.DEBUG) composable("paymentLab") { NativePaymentLab(nav) }
        composable("escrow") { NativeAccountGate(nav) { NativeEscrowScreen(nav) } }
        composable("premium") { NativeAccountGate(nav) { NativePremiumScreen(nav) } }
        composable("portfolio") { NativeAccountGate(nav) { NativePortfolioScreen(nav) } }
        composable("earnings") { NativeAccountGate(nav) { NativeEarningsScreen(nav) } }
        composable("settings") { NativeAccountGate(nav) { NativeSettingsScreen(nav) } }
        composable("ai") { NativeAccountGate(nav) { NativeSphereAIScreen(nav) } }
        composable("search/{q}") { NativeAccountGate(nav) { NativeSearchScreen(nav, it.arguments?.getString("q") ?: "") } }
        composable("editors?cat={cat}", arguments = listOf(optional("cat"))) { NativeAccountGate(nav) { EditorsScreen(nav, it.arguments?.getString("cat")) } }
        composable("editor/{id}") { NativeAccountGate(nav) { EditorProfileScreen(nav, it.arguments?.getString("id") ?: "") } }
        composable("postJob?editor={editor}&draft={draft}", arguments = listOf(optional("editor"), optional("draft"))) {
            NativeAccountGate(nav) { PostJobScreen(nav, it.arguments?.getString("editor"), it.arguments?.getString("draft")) }
        }
        composable("projectDrafts") { NativeAccountGate(nav) { ProjectDraftsScreen(nav) } }
        composable("jobs") { NativeAccountGate(nav) { JobsScreen(nav) } }
        composable("project/{id}") { NativeAccountGate(nav) { ProjectScreen(nav, it.arguments?.getString("id") ?: "") } }
        composable("bids/{id}") { NativeAccountGate(nav) { BidsScreen(nav, it.arguments?.getString("id") ?: "") } }
        composable("chats") { NativeAccountGate(nav) { ChatsScreen(nav) } }
        composable("chat/{id}") { NativeAccountGate(nav) { ChatScreen(nav, it.arguments?.getString("id") ?: "") } }
        composable("notifications") { NativeAccountGate(nav) { NotificationsScreen(nav) } }
        composable("profile") { NativeAccountGate(nav) { ProfileScreen(nav) } }
        composable("admin") { NativeAccountGate(nav) { NativeAdminScreen(nav) } }
        composable("support") { SupportScreen(nav) }
        composable("report?job={job}&user={user}", arguments = listOf(optional("job"), optional("user"))) {
            NativeAccountGate(nav) { ReportScreen(nav, it.arguments?.getString("job"), it.arguments?.getString("user")) }
        }
    }
}
