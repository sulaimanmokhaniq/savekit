package com.savekit.app

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

/**
 * Gives the home-screen icon the colour chosen in the app. The manifest declares one
 * launcher alias per colour; this enables the chosen one and disables the rest. The launcher
 * picks the change up on its own, usually within a few seconds.
 */
object LauncherIcon {

    private val THEMES = listOf("ember", "vault", "pulse", "tide", "classic", "rose", "gold")

    private fun component(context: Context, theme: String) = ComponentName(
        context,
        "${context.packageName}.Launcher${theme.replaceFirstChar { it.uppercase() }}",
    )

    /** Shows the icon of [theme]; an unknown theme falls back to the default icon. */
    fun apply(context: Context, theme: String) {
        val chosen = if (theme in THEMES) theme else THEMES.first()
        val packages = context.packageManager
        // Enable the new entry before disabling the old one, so the app is never
        // without a launcher entry.
        packages.setComponentEnabledSetting(
            component(context, chosen),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (other in THEMES) {
            if (other == chosen) continue
            packages.setComponentEnabledSetting(
                component(context, other),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
