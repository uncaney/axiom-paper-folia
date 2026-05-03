plugins {
    `java-library`
    alias(libs.plugins.paperweight.userdev)
    alias(libs.plugins.run.paper) // Adds runServer and runMojangMappedServer tasks for testing

    // Shades and relocates dependencies into our plugin jar. See https://imperceptiblethoughts.com/shadow/introduction/
    alias(libs.plugins.shadow)
}

group = "com.moulberry.axiom"
version = "5.0.4-folia.5+26.1.2"
description = "Serverside component for Axiom on Paper/Folia"

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(25))
}

repositories {
    maven("https://repo.viaversion.com") {
        content {
            includeGroup("com.viaversion")
        }
    }
    maven("https://maven.enginehub.org/repo/") { // WorldGuard
        content {
            includeGroup("com.sk89q.worldguard")
            includeGroup("com.sk89q.worldedit")
            includeGroup("com.sk89q.worldguard.worldguard-libs")
            includeGroup("com.sk89q.worldedit.worldedit-libs")
        }
    }
    // CoreProtect's Maven repo (maven.playpro.com) is Cloudflare-gated and returns 403 to
    // automated requests. We pin a local copy of the API jar instead — CoreProtect is
    // compileOnly so this only affects the build classpath.
    flatDir { dirs("libs") }
    mavenCentral()
}

dependencies {
    paperweight.paperDevBundle("26.1.2.build.53-stable")

    // Zstd Compression Library
    implementation(libs.zstd.jni)

    // LuckPerms event integration
    compileOnly(libs.luckperms)

    // ViaVersion support
    compileOnly(libs.viaversion.api)

    // WorldGuard support
    compileOnly(libs.worldguard.bukkit)

    // PlotSquared support
    implementation(platform(libs.bom.newest))
    compileOnly(libs.plotsquared.core)
    compileOnly(libs.plotsquared.bukkit) { isTransitive = false }

    // CoreProtect support
    compileOnly(libs.coreprotect)
}

tasks {
    assemble {
        dependsOn(shadowJar)
    }
    compileJava {
        options.encoding = Charsets.UTF_8.name() // We want UTF-8 for everything
        options.release.set(25)
    }
    javadoc {
        options.encoding = Charsets.UTF_8.name() // We want UTF-8 for everything
    }
    processResources {
        filteringCharset = Charsets.UTF_8.name() // We want UTF-8 for everything
        val props = mapOf(
                "name" to project.name,
                "version" to project.version,
                "description" to project.description,
                "apiVersion" to "26.1"
        )
        inputs.properties(props)
        filesMatching("plugin.yml") {
            expand(props)
        }
    }
}
