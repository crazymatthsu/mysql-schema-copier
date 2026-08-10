plugins {
    application
}

dependencies {
    // The provisioner module carries the shared local-env plumbing: config model + JDBC factory.
    implementation(project(":provisioner"))
    implementation(libs.mssql.jdbc)
}

application {
    applicationName = "trading-app"
    mainClass.set("com.mssqlclone.tradingapp.TradingAppDemo")
}

tasks.named<JavaExec>("run") {
    workingDir = rootProject.projectDir
}

sourceSets {
    create("integrationTest") {
        compileClasspath += sourceSets["main"].output
        runtimeClasspath += sourceSets["main"].output
    }
}

configurations["integrationTestImplementation"].extendsFrom(configurations["testImplementation"])
configurations["integrationTestRuntimeOnly"].extendsFrom(configurations["testRuntimeOnly"])

dependencies {
    "integrationTestImplementation"(project(":provisioner"))
    "integrationTestImplementation"(libs.mssql.jdbc)
}

val integrationTest by tasks.registering(Test::class) {
    description = "Runs integration tests against the local Podman SQL Server."
    group = "verification"
    testClassesDirs = sourceSets["integrationTest"].output.classesDirs
    classpath = sourceSets["integrationTest"].runtimeClasspath
    workingDir = rootProject.projectDir
    shouldRunAfter(tasks.named("test"))
    // Integration tests need a live database; keep them out of the default `check`.
    outputs.upToDateWhen { false }
}

tasks.named("check") {
    // Deliberately not wired to integrationTest: `./gradlew check` must pass with no container running.
}
