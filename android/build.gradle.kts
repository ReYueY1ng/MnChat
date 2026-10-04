allprojects {
    repositories {
        // 国内网络下 dl.google.com 直连会超时、repo.maven.apache.org 只有一两百 KB/s。
        // 依赖解析用的是**项目级**仓库（就是这里），settings.gradle.kts 里那份阿里云只
        // 覆盖插件解析，所以镜像必须补在这一层（与 settings 的写法保持一致）。
        // CI（GitHub runner）访问官方仓库正常，多这两个镜像对它没有影响。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
