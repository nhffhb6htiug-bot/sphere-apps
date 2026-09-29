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
        composable("editorDetails") { EditorDetailsScreen(nav) }
        composable("verification") { VerificationScreen(nav) }
        composable("home") { HomeScreen(nav) }
        composable("editors?cat={cat}", arguments = listOf(optional("cat"))) { EditorsScreen(nav, it.arguments?.getString("cat")) }
        composable("editor/{id}") { EditorProfileScreen(nav, it.arguments?.getString("id") ?: "") }
        composable("postJob?editor={editor}", arguments = listOf(optional("editor"))) { PostJobScreen(nav, it.arguments?.getString("editor")) }
        composable("jobs") { JobsScreen(nav) }
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
