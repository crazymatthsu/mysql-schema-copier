plugins {
    application
}

dependencies {
    implementation(libs.mssql.jdbc)
    implementation(libs.picocli)
    implementation(libs.snakeyaml)
}

application {
    applicationName = "local-db"
    mainClass.set("com.mssqlclone.localenv.cli.LocalDbCli")
}

tasks.named<JavaExec>("run") {
    // Scripts invoke the installed launcher; `gradle run` is for ad-hoc use from the repo root.
    workingDir = rootProject.projectDir
}
