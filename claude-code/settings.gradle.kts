rootProject.name = "mssql-local-clone"

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

include("provisioner")
include("trading-app")
