pluginManagement {
    repositories {
        val proxy = System.getenv("MINIMAL_SLEEP_MAVEN_PROXY")?.takeIf { it.isNotBlank() }
        if (proxy != null) {
            maven {
                url = uri(proxy)
                isAllowInsecureProtocol = true
            }
        } else {
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        val proxy = System.getenv("MINIMAL_SLEEP_MAVEN_PROXY")?.takeIf { it.isNotBlank() }
        if (proxy != null) {
            maven {
                url = uri(proxy)
                isAllowInsecureProtocol = true
            }
        } else {
            google()
            mavenCentral()
        }
    }
}

rootProject.name = "minimal-sleep"
include(":app")
