import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.api.tasks.testing.logging.TestExceptionFormat

plugins {
    java
}

allprojects {
    group = "com.mssqlclone"
    version = "0.1.0"
}

// Type-safe `libs` accessors are not visible inside `subprojects {}`, so resolve the catalog explicitly.
val catalog = extensions.getByType<VersionCatalogsExtension>().named("libs")
val javaVersion = catalog.findVersion("java").orElseThrow().requiredVersion.toInt()

subprojects {
    apply(plugin = "java")

    repositories {
        mavenCentral()
    }

    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(javaVersion))
        }
    }

    dependencies {
        "testImplementation"(platform(catalog.findLibrary("junit-bom").orElseThrow()))
        "testImplementation"(catalog.findLibrary("junit-jupiter").orElseThrow())
        "testRuntimeOnly"(catalog.findLibrary("junit-platform-launcher").orElseThrow())
    }

    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
        options.compilerArgs.add("-Xlint:all,-serial,-processing")
    }

    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
        testLogging {
            events("passed", "skipped", "failed")
            exceptionFormat = TestExceptionFormat.FULL
            showStandardStreams = providers.gradleProperty("showTestOutput").isPresent
        }
    }
}
