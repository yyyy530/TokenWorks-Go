package io.github.yyyy530.tokenworks_go

import android.content.Context
import android.system.Os
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.json.JSONObject
import org.tukaani.xz.XZInputStream
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.SimpleFileVisitor
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.attribute.BasicFileAttributes
import java.security.DigestInputStream
import java.security.MessageDigest

internal class LocalRuntimeBundle(private val context: Context) {
    private val assetDir = "tokenworks/runtime"
    private val manifest by lazy {
        context.assets.open("$assetDir/manifest.json").bufferedReader().use {
            JSONObject(it.readText())
        }
    }
    val available: Boolean
        get() = context.assets.list(assetDir)?.contains("manifest.json") == true

    fun install(progress: (Int) -> Unit): Path {
        val version = manifest.getString("runtimeVersion")
        check(manifest.getString("abi") == "arm64-v8a")
        val base = Files.createDirectories(context.noBackupFilesDir.toPath().resolve("local-linux")).toRealPath()
        val root = base.resolve("rootfs")
        val marker = ".tokenworks-runtime-version"
        if (Files.exists(root, NOFOLLOW_LINKS)) {
            val installed = root.resolve(marker)
            if (!Files.isRegularFile(installed, NOFOLLOW_LINKS) ||
                Files.readAllBytes(installed).toString(Charsets.UTF_8) != version
            ) {
                throw RuntimeFailure("installed-version")
            }
            return root
        }

        val staging = base.resolve("staging")
        deleteTree(staging)
        val expectedSize = manifest.getLong("uncompressedBytes")
        if (base.toFile().usableSpace < expectedSize + 128L * 1024 * 1024) {
            throw RuntimeFailure("insufficient-space")
        }
        Files.createDirectory(staging)
        try {
            unpack(staging, expectedSize, progress)
            check(Files.isRegularFile(staging.resolve("opt/node/bin/node"), NOFOLLOW_LINKS))
            check(Files.isRegularFile(staging.resolve("usr/local/bin/dsh"), NOFOLLOW_LINKS))
            Files.write(staging.resolve(marker), version.toByteArray(Charsets.UTF_8))
            Files.move(staging, root, ATOMIC_MOVE)
        } finally {
            deleteTree(staging)
        }
        return root
    }

    private fun unpack(root: Path, expectedSize: Long, progress: (Int) -> Unit) {
        val sha256 = MessageDigest.getInstance("SHA-256")
        val asset = manifest.getString("rootfs")
        val directoryModes = mutableListOf<Pair<Path, Int>>()
        var extracted = 0L
        var reported = 0
        val buffer = ByteArray(64 * 1024)
        DigestInputStream(context.assets.open("$assetDir/$asset"), sha256).buffered().use { raw ->
            XZInputStream(raw).buffered().use { decoded ->
                TarArchiveInputStream(decoded).use { tar ->
                    while (true) {
                        val entry = tar.nextEntry ?: break
                        val relative = Paths.get(entry.name)
                        val target = root.resolve(relative).normalize()
                        check(!relative.isAbsolute && target != root && target.startsWith(root))
                        val parent = target.parent
                        check(parent.toRealPath() == parent)
                        when {
                            entry.isDirectory -> {
                                Files.createDirectories(target)
                                check(Files.isDirectory(target, NOFOLLOW_LINKS))
                                directoryModes += target to (entry.mode and 0x1ff)
                            }
                            entry.isSymbolicLink -> {
                                val link = Paths.get(entry.linkName)
                                check(!link.isAbsolute && parent.resolve(link).normalize().startsWith(root))
                                Files.createSymbolicLink(target, link)
                            }
                            entry.isFile && !entry.isLink -> {
                                check(!Files.exists(target, NOFOLLOW_LINKS))
                                check(entry.size >= 0 && entry.size <= expectedSize - extracted)
                                Files.newOutputStream(target).use { file ->
                                    while (true) {
                                        val count = tar.read(buffer)
                                        if (count < 0) break
                                        file.write(buffer, 0, count)
                                    }
                                }
                                Os.chmod(target.toString(), entry.mode and 0x1ff)
                                extracted += entry.size
                                val percent = (100 * extracted / expectedSize).toInt().coerceAtMost(99)
                                if (percent > reported) {
                                    reported = percent
                                    progress(percent)
                                }
                            }
                            else -> error("Unsupported rootfs entry type")
                        }
                    }
                    // Consume XZ padding and validate its footer before trusting the asset digest.
                    while (decoded.read(buffer) != -1) Unit
                }
            }
        }
        val actual = sha256.digest().joinToString("") { "%02x".format(it) }
        check(actual == manifest.getString("rootfsSha256"))
        check(extracted == expectedSize)
        directoryModes.asReversed().forEach { (directory, mode) -> Os.chmod(directory.toString(), mode) }
    }

    private fun deleteTree(path: Path) {
        if (!Files.exists(path, NOFOLLOW_LINKS)) return
        Files.walkFileTree(path, object : SimpleFileVisitor<Path>() {
            override fun preVisitDirectory(dir: Path, attrs: BasicFileAttributes): FileVisitResult {
                Os.chmod(dir.toString(), 0x1c0) // 0700
                return FileVisitResult.CONTINUE
            }

            override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                Files.delete(file)
                return FileVisitResult.CONTINUE
            }

            override fun postVisitDirectory(dir: Path, exc: java.io.IOException?): FileVisitResult {
                if (exc != null) throw exc
                Files.delete(dir)
                return FileVisitResult.CONTINUE
            }
        })
    }
}

internal class RuntimeFailure(val code: String) : Exception()
