package com.hissamuddin.eidos.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.hissamuddin.eidos.ui.chat.ChatScreen
import com.hissamuddin.eidos.ui.home.HomeScreen
import com.hissamuddin.eidos.ui.kb.KbScreen
import com.hissamuddin.eidos.ui.memory.MemoryScreen
import com.hissamuddin.eidos.ui.settings.DiagnosticsScreen
import com.hissamuddin.eidos.ui.settings.SettingsScreen

/**
 * Compose entry point. Hosts a Material 3 bottom nav bar + NavHost over
 * the five top-level [Destination]s.
 *
 * A0 only wires routing + placeholder screens; each phase replaces one
 * screen with its real implementation.
 */
@Composable
fun EidosApp() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                Destination.entries.forEach { dest ->
                    val selected = backStackEntry?.destination
                        ?.hierarchy
                        ?.any { it.route == dest.route } == true
                        || (currentRoute == Destination.ROUTE_DIAGNOSTICS && dest == Destination.SETTINGS)

                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(dest.route) {
                                popUpTo(navController.graph.startDestinationId) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = {
                            Icon(
                                imageVector = dest.icon,
                                contentDescription = stringResource(dest.labelRes),
                            )
                        },
                        label = { Text(stringResource(dest.labelRes)) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = Destination.HOME.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(Destination.HOME.route) { HomeScreen() }
            composable(Destination.CHAT.route) { ChatScreen() }
            composable(Destination.MEMORY.route) { MemoryScreen() }
            composable(Destination.KB.route) { KbScreen() }
            composable(Destination.SETTINGS.route) {
                SettingsScreen(onOpenDiagnostics = {
                    navController.navigate(Destination.ROUTE_DIAGNOSTICS)
                })
            }
            composable(Destination.ROUTE_DIAGNOSTICS) {
                DiagnosticsScreen(onBack = { navController.popBackStack() })
            }
        }
    }
}
