allprojects {
    repositories {
        google()
        mavenCentral()
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

// flutter_blue_plus 1.34.5 的 compileSdk 仍为 33，而它依赖的 AndroidX 组件要求 34+；
// 2.x 与 connectivity_plus 的 Linux 传递依赖冲突，无法升级，故仅对该插件抬高 compileSdk。
subprojects {
    if (name == "flutter_blue_plus") {
        afterEvaluate {
            val android = extensions.findByName("android")
            if (android != null) {
                runCatching {
                    android.javaClass
                        .getMethod("setCompileSdk", java.lang.Integer::class.java)
                        .invoke(android, 36)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
