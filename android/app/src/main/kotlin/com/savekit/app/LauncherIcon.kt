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
        // Each change makes the launcher reload the app, so only touch entries
        // that are not already as wanted. Usually that is none of them.
        fun set(theme: String, enabled: Boolean) {
            val name = component(context, theme)
            val current = packages.getComponentEnabledSetting(name)
            val isEnabled = when (current) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
                // Default: as the manifest says, where only Ember is enabled.
                else -> theme == THEMES.first()
            }
            if (isEnabled == enabled) return
            packages.setComponentEnabledSetting(
                name,
                if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        // Enable the new entry before disabling the old one, so the app is never
        // without a launcher entry.
        set(chosen, true)
        for (other in THEMES) {
            if (other != chosen) set(other, false)
        }
    }
}
