package io.github.yyyy530.tokenworks_go

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.system.Os
import android.system.OsConstants
import android.util.Log
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

internal class LocalRuntime(private val context: Context) {
    private val bundle = LocalRuntimeBundle(context)
    private val executor = Executors.newSingleThreadExecutor()
    private val supported = Build.VERSION.SDK_INT >= 26 &&
        Build.SUPPORTED_ABIS.firstOrNull() == "arm64-v8a"

    @Volatile private var state = State("stopped")
    private var engine: Engine? = null
    private var access: Access? = null

    fun status(): Map<String, Any?> {
        val current = when {
            !bundle.available -> State("missing")
            !supported -> State("unsupported")
            else -> state
        }
        return mapOf("phase" to current.phase, "progress" to current.progress, "error" to current.error)
    }

    @Synchronized fun connection(): Access? = access?.takeIf {
        state.phase == "running" && engine?.process?.isAlive == true
    }

    @Synchronized fun start() {
        if (!supported || !bundle.available || state.phase in busyPhases || engine != null) return
        state = State("installing")
        executor.execute { boot() }
    }

    @Synchronized fun stop() {
        val running = engine ?: return
        if (state.phase in busyPhases) return
        state = State("stopping")
        access = null
        executor.execute {
            val stopped = running.stop()
            synchronized(this) {
                if (stopped) engine = null
                state = if (stopped) State("stopped") else State("error", error = "stop-failed")
            }
        }
    }

    private fun boot() {
        var launching: Engine? = null
        try {
            val root = bundle.install { state = State("installing", it) }
            state = State("starting")
            applyDns(root)
            val port = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }
            val process = command(root, port).start()
            val run = Engine(process, port)
            launching = run
            synchronized(this) { engine = run }
            run.readOutput { exited(run) }
            val token = run.token.get(90, TimeUnit.SECONDS)
            synchronized(this) {
                check(process.isAlive)
                access = Access(port, token)
                state = State("running")
            }
        } catch (failure: Exception) {
            Log.w("TokenWorksRuntime", "Local startup failed: ${failure.javaClass.simpleName}")
            val stopped = launching?.stop() ?: true
            synchronized(this) {
                if (stopped) engine = null
                access = null
                state = State(
                    "error", error = if (!stopped) "stop-failed" else (failure as? RuntimeFailure)?.code ?: "start-failed",
                )
            }
        }
    }

    @Synchronized private fun exited(run: Engine) {
        if (engine !== run || state.phase != "running") return
        engine = null
        access = null
        state = State("error", error = "engine-exited")
    }

    private fun applyDns(root: Path) {
        val network = context.getSystemService(ConnectivityManager::class.java) ?: return
        val servers = network.getLinkProperties(network.activeNetwork)?.dnsServers.orEmpty()
            .mapNotNull { it.hostAddress?.substringBefore('%') }.distinct().take(3)
        val resolvers = root.resolve("etc/resolv.conf")
        if (servers.isNotEmpty() && Files.isRegularFile(resolvers, NOFOLLOW_LINKS) &&
            resolvers.parent.toRealPath() == resolvers.parent
        ) {
            Files.write(
                resolvers,
                (servers.joinToString("\n") { "nameserver $it" } + "\noptions timeout:2 attempts:2\n")
                    .toByteArray(Charsets.UTF_8),
            )
        }
    }

    private fun command(root: Path, port: Int): ProcessBuilder {
        val libraries = context.applicationInfo.nativeLibraryDir
        val tmp = File(context.cacheDir, "local-proot").apply { check(isDirectory || mkdirs()) }
        val proot = listOf(
            "$libraries/libproot.so", "--kill-on-exit", "--link2symlink", "--sysvipc",
            "-L", "-0", "--rootfs=$root", "--cwd=/root",
            "-b", "/dev", "-b", "/dev/urandom:/dev/random", "-b", "/proc",
            "-b", "/proc/self/fd:/dev/fd", "-b", "/proc/self/fd/0:/dev/stdin",
            "-b", "/proc/self/fd/1:/dev/stdout", "-b", "/proc/self/fd/2:/dev/stderr",
            "-b", "/sys", "-b", "$root/var/lib/dsh-app/empty:/sys/fs/selinux",
            "-b", "$root/var/lib/dsh-app/shm:/dev/shm", "-b", "/system", "-b", "/apex",
            "/usr/bin/env", "-i", "HOME=/root", "USER=root", "LOGNAME=root", "SHELL=/bin/bash",
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "LANG=C.UTF-8", "TERM=xterm-256color", "TMPDIR=/tmp", "DSH_HOME=/root/.dsh",
            "UV_USE_IO_URING=0", "NARB_DISABLE_NATIVE_CACHE=1",
            "NODE_OPTIONS=--dns-result-order=ipv4first --import=/opt/dsh-go/direct/proot-dns.mjs",
            "/bin/sh", "-c",
            "echo tokenworks-dsh-pid: \$\$; exec /usr/local/bin/dsh web --host 127.0.0.1 --port $port --no-open",
        )
        val shell = listOf("/system/bin/sh", "-c", "echo tokenworks-proot-pid: \$\$; exec \"\$@\"", "tokenworks")
        return ProcessBuilder(shell + proot).directory(context.filesDir).redirectErrorStream(true).apply {
            environment().clear()
            environment().putAll(mapOf(
                "PATH" to "/system/bin:/system/xbin",
                "ANDROID_ROOT" to "/system",
                "ANDROID_DATA" to "/data",
                "PROOT_LOADER" to "$libraries/libproot-loader.so",
                "PROOT_L2S_DIR" to "$root/root/.l2s",
                "PROOT_TMP_DIR" to tmp.absolutePath,
                "TMPDIR" to tmp.absolutePath,
                "LD_LIBRARY_PATH" to libraries,
            ))
        }
    }

    internal class Access(val port: Int, val token: String) {
        val origin: String get() = "http://127.0.0.1:$port"
    }

    private class State(val phase: String, val progress: Int = 0, val error: String? = null)

    private class Engine(val process: Process, port: Int) {
        val token = CompletableFuture<String>()
        private val ready = Regex("^dsh web: http://127\\.0\\.0\\.1:$port/\\?token=([A-Za-z0-9_-]{43})(?:\\s|$)")
        @Volatile private var pid: Int? = null
        @Volatile private var guestPid: Int? = null

        fun readOutput(onExit: () -> Unit) {
            thread(name = "tokenworks-dsh-output", isDaemon = true) {
                try {
                    process.inputStream.bufferedReader().use { reader ->
                        pid = reader.readLine()?.let { readPid(it, "tokenworks-proot-pid: ") }
                        reader.forEachLine { line ->
                            if (guestPid == null) guestPid = readPid(line, "tokenworks-dsh-pid: ")
                            ready.find(line)?.groupValues?.get(1)?.let { token.complete(it) }
                        }
                    }
                } finally {
                    process.waitFor()
                    token.completeExceptionally(RuntimeFailure("engine-exited"))
                    onExit()
                }
            }
        }

        fun stop(): Boolean {
            if (!process.isAlive) return true
            val child = pid ?: return false
            val guest = guestPid
            if (token.isDone && !token.isCompletedExceptionally && guest != null &&
                guest != child && parentPid(guest) == child
            ) {
                try {
                    Os.kill(guest, OsConstants.SIGTERM)
                    if (process.waitFor(5, TimeUnit.SECONDS)) return true
                } catch (_: Exception) {
                    if (!process.isAlive) return true
                }
            }
            return try {
                // PRoot handles SIGQUIT by terminating the traced Linux processes.
                Os.kill(child, OsConstants.SIGQUIT)
                process.waitFor(8, TimeUnit.SECONDS)
            } catch (_: Exception) {
                !process.isAlive
            }
        }

        private fun readPid(line: String, prefix: String): Int? =
            line.takeIf { it.startsWith(prefix) }?.removePrefix(prefix)?.toIntOrNull()?.takeIf { it > 1 }

        private fun parentPid(pid: Int): Int? = try {
            File("/proc/$pid/status").useLines { lines ->
                lines.firstOrNull { it.startsWith("PPid:") }?.substringAfter(':')?.trim()?.toIntOrNull()
            }
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        val busyPhases = setOf("installing", "starting", "stopping")
    }
}
