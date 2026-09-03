// ignore_for_file: prefer_initializing_formals
/// The `fsb` executable engine: resolves a cube, enforces it around one
/// command and maps the outcome to a process exit code.
///
/// Pure Dart like the rest of `lib/src`: the filesystem/shell boundary
/// ([ExecutionEnv]) and the output sinks are injected, so the runner runs
/// against [MemoryExecutionEnv] in tests with no processes at all.
///
/// Exit-code contract:
/// - the child's exit code passes through unchanged;
/// - 127 — a policy denial (the `fa_cube[<name>]:` note reaches stderr,
///   like a shell reporting "command not found") or a kernel-wrapper
///   startup failure;
/// - 64 — usage/spec errors: an unreadable or invalid manifest
///   (`fsb: <reason>` on stderr, fail-closed — never an unconfined run).
///
/// Cache behavior follows the manifest: when `spec.cache` is enabled the
/// content-addressed entry is restored before the run and saved after it,
/// around the sandboxed execution.
library;

import '../cube/backends/cube_backend.dart';
import '../cube/config/cube_spec.dart';
import '../cube/config/resource_limits.dart';
import '../env/execution_env.dart';
import '../exceptions.dart';
import '../cube/runtime/cache_manager.dart';
import '../cube/runtime/cube_resolver.dart';
import '../cube/runtime/sandboxed_env.dart';
import '../cube/runtime/sandboxed_shell.dart';
import 'fsb_args.dart';

/// Runs console commands inside a resolved cube.
final class FsbRunner {
  /// Creates a runner over [env] (the delegate filesystem and shell).
  ///
  /// [homeDir] expands `~/` paths in manifest references; [os] names the
  /// host platform for kernel-mode cubes (`Platform.operatingSystem` in
  /// the CLI). [writeStdout]/[writeStderr] receive the command's streamed
  /// output and the runner's own diagnostics.
  FsbRunner({
    required ExecutionEnv env,
    required String? homeDir,
    required String os,
    required void Function(String chunk) writeStdout,
    required void Function(String chunk) writeStderr,
  }) : _env = env,
       _homeDir = homeDir,
       _os = os,
       _writeStdout = writeStdout,
       _writeStderr = writeStderr;

  final ExecutionEnv _env;
  final String? _homeDir;
  final String _os;
  final void Function(String chunk) _writeStdout;
  final void Function(String chunk) _writeStderr;

  /// Runs [args].command inside the resolved cube; returns the exit code.
  Future<int> runCommand(FsbRunArgs args) async {
    final spec = await _resolveSpec(
      path: args.cubeConfigPath,
      name: args.cubeName,
    );
    if (spec == null) return 64;
    final effective = args.backend == null
        ? spec
        : _withBackend(spec, args.backend!);
    final sandbox = SandboxedExecutionEnv(
      _env,
      effective,
      homeDir: _homeDir,
      workspaceRoot: _env.cwd,
      os: _os,
    );
    final cache = CubeCacheManager(sandbox, effective);
    // Best-effort cache lifecycle: one warning line on failure, never a
    // blocker (a corrupt cache entry must not take the run down).
    try {
      await cache.restoreIfNeeded();
    } on Object catch (error) {
      _writeStderr('fsb: cache restore failed: $error\n');
    }
    var stderrStreamed = false;
    final result = await sandbox.exec(
      _commandLine(args.command),
      options: ShellExecOptions(
        cwd: _env.cwd,
        onStdout: _writeStdout,
        onStderr: (chunk) {
          stderrStreamed = true;
          _writeStderr(chunk);
        },
        timeout: args.timeout == null ? null : Duration(seconds: args.timeout!),
      ),
    );
    try {
      await cache.save();
    } on Object catch (error) {
      _writeStderr('fsb: cache save failed: $error\n');
    }
    var exitCode = 0;
    switch (result) {
      case Ok(:final value):
        // A policy denial never reaches the inner shell, so its
        // `fa_cube[<name>]:` note arrives only in the result — forward it
        // when nothing streamed (a real command's stderr already did).
        if (!stderrStreamed && value.stderr.isNotEmpty) {
          // The note is a bare line; the trailing newline keeps it from
          // gluing onto whatever follows on stderr.
          _writeStderr('${value.stderr}\n');
        }
        exitCode = value.exitCode;
      case Err(:final error):
        // Kernel-wrapper startup failures carry their own
        // `fa_cube[<name>]: kernel backend ...` note verbatim.
        _writeStderr('${error.message}\n');
        exitCode = 127;
    }
    return exitCode;
  }

  /// Parses [args].path and prints a policy summary; exit 64 on any
  /// manifest problem.
  Future<int> validateSpec(FsbValidateArgs args) async {
    try {
      final spec = await CubeResolver.resolve(
        env: _env,
        path: args.path,
        homeDir: _homeDir,
      );
      _writeStdout(_summary(spec!));
      return 0;
    } on ConfigException catch (error) {
      _writeStderr('fsb: ${error.message}');
      return 64;
    }
  }

  /// Stages the kernel profile and prints the wrapped command line
  /// (kernel mode), or a policy-mode note (`backend: policy`, or a
  /// platform without an enforcing backend).
  Future<int> wrapCommand(FsbWrapArgs args) async {
    final spec = await _resolveSpec(
      path: args.cubeConfigPath,
      name: args.cubeName,
    );
    if (spec == null) return 64;
    if (spec.backend != CubeBackendMode.kernel ||
        !cubeBackendForPlatform(_os).enforces) {
      _writeStdout(
        'policy mode: command runs unwrapped; enforcement is lexical only',
      );
      return 0;
    }
    final shell = SandboxedShell(_env, spec, fs: _env, os: _os);
    _writeStdout(await shell.prepare(_commandLine(args.command)));
    return 0;
  }

  /// Prints one `describe()` line per known platform plus the current one.
  int describeBackends() {
    const known = ['macos', 'linux', 'windows'];
    for (final os in [...known, if (!known.contains(_os)) _os]) {
      _writeStdout('$os: ${cubeBackendForPlatform(os).describe()}\n');
    }
    return 0;
  }

  /// Resolves the cube manifest; fail-closed: an unreadable or invalid
  /// manifest prints `fsb: <reason>` to stderr and yields `null` (exit 64
  /// for the caller).
  Future<CubeSpec?> _resolveSpec({String? path, String? name}) async {
    try {
      return await CubeResolver.resolve(
        env: _env,
        path: path,
        name: name,
        homeDir: _homeDir,
      );
    } on ConfigException catch (error) {
      _writeStderr('fsb: ${error.message}');
      return null;
    }
  }

  /// A copy of [spec] with the backend forced to [backend] (the
  /// `--backend` override). [CubeSpec] is immutable with no `copyWith`, so
  /// the copy rebuilds the top level and shares the policy objects.
  CubeSpec _withBackend(CubeSpec spec, CubeBackendMode backend) => CubeSpec(
    name: spec.name,
    description: spec.description,
    backend: backend,
    tools: spec.tools,
    network: spec.network,
    filesystem: spec.filesystem,
    env: spec.env,
    resources: spec.resources,
    cache: spec.cache,
  );

  /// The command joined into one `sh -c` line, every word shell-quoted:
  /// the policy engine then judges exactly the text the shell will see,
  /// so no `$VAR`/glob/`~` word can expand past it.
  String _commandLine(List<String> words) => words.map(shellQuote).join(' ');

  /// One-line-per-concern rendering of [spec] for `fsb validate`.
  String _summary(CubeSpec spec) => [
    'name: ${spec.name}',
    if (spec.description != null) 'description: ${spec.description}',
    'backend: ${spec.backend.name}',
    'tools: ${spec.tools.allow.length} allow, ${spec.tools.deny.length} deny',
    'network: ${spec.network.allow.length} allow, '
        '${spec.network.deny.length} deny',
    'filesystem: workspace ${spec.filesystem.workspace}, '
        '${spec.filesystem.mounts.length} mounts',
    'env: ${spec.env.vars.length} vars',
    'resources: ${_resourcesSummary(spec.resources)}',
    _cacheSummary(spec),
  ].join('\n');

  String _resourcesSummary(CubeResourceLimits limits) {
    final parts = [
      if (limits.cpu != null) 'cpu ${limits.cpu}',
      if (limits.memoryBytes != null) 'memory ${limits.memoryBytes}B',
      if (limits.diskBytes != null) 'disk ${limits.diskBytes}B',
      if (limits.timeout != null) 'timeout ${limits.timeout!.inSeconds}s',
    ];
    return parts.isEmpty ? 'none' : parts.join(', ');
  }

  String _cacheSummary(CubeSpec spec) {
    if (!spec.cache.enabled) return 'cache: disabled';
    final ttl = spec.cache.ttl;
    return 'cache: enabled (${spec.cache.paths.length} paths, '
        'restore ${spec.cache.restore ? 'on' : 'off'}'
        '${ttl == null ? '' : ', ttl ${ttl.inSeconds}s'})';
  }
}
