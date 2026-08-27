allprojects {
    repositories {
        google()
        mavenCentral()
        // Required by web3auth_flutter: the native Android Web3Auth SDK is
        // published on JitPack, not Maven Central. Without this, Gradle
        // dependency resolution fails at build time (not analyze/pub-get time).
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
