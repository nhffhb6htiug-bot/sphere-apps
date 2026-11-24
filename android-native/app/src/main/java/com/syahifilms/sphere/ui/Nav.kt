package com.syahifilms.sphere.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.activity.compose.BackHandler
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument

@Composable
fun SphereNav() {
    val nav = rememberNavController()
    val entry by nav.currentBackStackEntryAsState()
    BackHandler(enabled = entry?.destination?.route == "home" && nav.previousBackStackEntry == null) { /* Stay on Sphere home. */ }
    val optional = { name: String -> navArgument(name) { type = NavType.StringType; nullable = true; defaultValue = null } }
    NavHost(navController = nav, startDestination = "splash") {
        composable("splash") { SplashScreen(nav) }
        composable("welcome") { WelcomeScreen(nav) }
        composable("login") { LoginScreen(nav) }
        composable("signup") { SignupScreen(nav) }
        composable("chooseRole") { ChooseRoleScreen(nav) }
        composable("editorDetails") { EditorDetailsScreen(nav) }
        composable("verification") { VerificationScreen(nav) }
        composable("home") { HomeScreen(nav) }
        composable("saved") { SavedEditorsScreen(nav) }
        composable("verifiedPc") { VerifiedPcScreen(nav) }
        composable("vault") { VaultNativeScreen(nav) }
        composable("payments") { NativePaymentsScreen(nav) }
        composable("escrow") { NativeEscrowScreen(nav) }
        composable("premium") { NativePremiumScreen(nav) }
        composable("portfolio") { NativePortfolioScreen(nav) }
        composable("earnings") { NativeEarningsScreen(nav) }
        composable("settings") { NativeSettingsScreen(nav) }
        composable("ai") { NativeSphereAIScreen(nav) }
        composable("search/{q}") { NativeSearchScreen(nav, it.arguments?.getString("q") ?: "") }
        composable("editors?cat={cat}", arguments = listOf(optional("cat"))) { EditorsScreen(nav, it.arguments?.getString("cat")) }
        composable("editor/{id}") { EditorProfileScreen(nav, it.arguments?.getString("id") ?: "") }
        composable("postJob?editor={editor}", arguments = listOf(optional("editor"))) { PostJobScreen(nav, it.arguments?.getString("editor")) }
        composable("jobs") { JobsScreen(nav) }
        composable("drafts") { NativeDraftsScreen(nav) }
        composable("draft/{id}") { PostJobScreen(nav, null, it.arguments?.getString("id")) }
        composable("adminNative") { NativeAdminScreen(nav) }
        composable("project/{id}") { ProjectScreen(nav, it.arguments?.getString("id") ?: "") }
        composable("bids/{id}") { BidsScreen(nav, it.arguments?.getString("id") ?: "") }
        composable("chats") { ChatsScreen(nav) }
        composable("chat/{id}") { ChatScreen(nav, it.arguments?.getString("id") ?: "") }
        composable("notifications") { NotificationsScreen(nav) }
        composable("profile") { ProfileScreen(nav) }
        composable("support") { SupportScreen(nav) }
        composable("report?job={job}", arguments = listOf(optional("job"))) { ReportScreen(nav, it.arguments?.getString("job")) }
    }
}
