import 'dart:convert';

import 'package:flutter_sandbox/flutter_sandbox.dart';
import 'package:flutter_sandbox/src/cli/fsb_args.dart';
import 'package:flutter_sandbox/src/cli/sandbox_runner.dart';
import 'package:test/test.dart';

/// A [Shell] returning a canned result, streaming it through the exec
/// callbacks and recording every invocation.
class _RecordingShell implements Shell {
  final commands = <String>[];
  final options = <ShellExecOptions?>[];

  /// The canned outcome of every exec.
  Result<ShellExecResult, ExecutionError> result = const Ok(
    ShellExecResult(stdout: '', stderr: '', exitCode: 0),
  );

  @override
  Future<Result<ShellExecResult, ExecutionError>> exec(
    String command, {
    ShellExecOptions? options,
  }) async {
    commands.add(command);
    this.options.add(options);
    // An Err result has nothing to stream — the runner reports it.
    if (result case Ok(:final value)) {
      options?.onStdout?.call(value.stdout);
      options?.onStderr?.call(value.stderr);
    }
    return result;
  }
}

/// A runner over a [MemoryExecutionEnv] with buffered output sinks.
typedef _Harness = ({
  FsbRunner runner,
  MemoryExecutionEnv env,
  _RecordingShell shell,
  StringBuffer out,
  StringBuffer err,
});

_Harness _harness({String os = 'linux'}) {
  final shell = _RecordingShell();
  final env = MemoryExecutionEnv(cwd: '/ws', shell: shell);
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = FsbRunner(
    env: env,
    homeDir: '/home/test',
    os: os,
    writeStdout: out.write,
    writeStderr: err.write,
  );
  return (runner: runner, env: env, shell: shell, out: out, err: err);
}

/// Writes a minimal cube manifest under `.fah/cubes/`.
Future<void> _writeCube(
  MemoryExecutionEnv env,
  String name, {
  List<String> allow = const ['echo'],
  String backend = 'policy',
  String? cachePaths,
}) async {
  final yaml = [
    'apiVersion: fa/v1',
    'kind: Cube',
    'metadata:',
    '  name: $name',
    'spec:',
    '  backend: $backend',
    '  tools:',
    '    allow: [${allow.join(', ')}]',
    if (cachePaths != null) ...[
      '  cache:',
      '    enabled: true',
      '    paths: [$cachePaths]',
    ],
  ].join('\n');
  (await env.writeFile('.fah/cubes/$name.yaml', '$yaml\n')).getOrThrow();
}

void main() {
  group('FsbRunner.runCommand', () {
    test('a denied command exits 127 with the fa_cube note', () async {
      final h = _harness();
      await _writeCube(h.env, 'git-only', allow: ['git']);
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'git-only', command: const ['rm', '-rf', './x']),
      );
      expect(code, 127);
      expect(h.err.toString(), startsWith('fa_cube[git-only]:'));
      expect(
        h.err.toString(),
        contains("command 'rm' not in cube 'git-only' allowlist"),
      );
      // The inner shell is never reached for a denied command.
      expect(h.shell.commands, isEmpty);
    });

    test('a kernel-wrapper startup failure exits 127 with its note', () async {
      final h = _harness();
      h.shell.result = const Err(
        ExecutionError(
          ExecutionErrorCode.spawnError,
          'fa_cube[echo-box]: kernel backend unshare failed: EPERM',
        ),
      );
      await _writeCube(h.env, 'echo-box');
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'echo-box', command: const ['echo', 'hi']),
      );
      expect(code, 127);
      expect(
        h.err.toString(),
        'fa_cube[echo-box]: kernel backend unshare failed: EPERM\n',
      );
    });

    test(
      'an allowed command streams output and passes the exit code',
      () async {
        final h = _harness();
        h.shell.result = const Ok(
          ShellExecResult(stdout: 'hi\n', stderr: '', exitCode: 0),
        );
        await _writeCube(h.env, 'echo-box');
        final code = await h.runner.runCommand(
          FsbRunArgs(cubeName: 'echo-box', command: const ['echo', 'hi']),
        );
        expect(code, 0);
        expect(h.out.toString(), 'hi\n');
        expect(h.shell.commands, ["'echo' 'hi'"]);
      },
    );

    test('streamed stderr reaches the sink exactly once', () async {
      final h = _harness();
      h.shell.result = const Ok(
        ShellExecResult(stdout: '', stderr: 'boom', exitCode: 3),
      );
      await _writeCube(h.env, 'echo-box');
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'echo-box', command: const ['echo', 'boom']),
      );
      expect(code, 3);
      expect(h.err.toString(), 'boom');
    });

    test('--timeout and --backend reach the exec options', () async {
      final h = _harness();
      await _writeCube(h.env, 'echo-box');
      final code = await h.runner.runCommand(
        FsbRunArgs(
          cubeName: 'echo-box',
          backend: CubeBackendMode.kernel,
          timeout: 7,
          command: const ['echo', 'hi'],
        ),
      );
      expect(code, 0);
      final options = h.shell.options.single;
      expect(options?.timeout, const Duration(seconds: 7));
    });

    test('the exec runs with the workspace as its cwd', () async {
      final h = _harness();
      await _writeCube(h.env, 'echo-box');
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'echo-box', command: const ['echo', 'hi']),
      );
      expect(code, 0);
      expect(h.shell.options.single?.cwd, '/ws');
    });

    test('a missing manifest fails closed with exit 64', () async {
      final h = _harness();
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'nope', command: const ['echo', 'hi']),
      );
      expect(code, 64);
      expect(
        h.err.toString(),
        'fsb: cube: file not found: /ws/.fah/cubes/nope.yaml',
      );
    });

    test('an invalid manifest fails closed with exit 64', () async {
      final h = _harness();
      (await h.env.writeFile(
        '.fah/cubes/bad.yaml',
        'apiVersion: fa/v2\nkind: Cube\nmetadata:\n  name: bad\n',
      )).getOrThrow();
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'bad', command: const ['echo', 'hi']),
      );
      expect(code, 64);
      expect(h.err.toString(), startsWith('fsb: '));
      expect(h.err.toString(), contains('apiVersion'));
    });

    test('run restores the cache before and saves it after', () async {
      final h = _harness();
      await _writeCube(h.env, 'cached', cachePaths: '/workspace/.cache');
      final spec = (await CubeResolver.resolve(
        env: h.env,
        name: 'cached',
        homeDir: '/home/test',
      ))!;
      final key = cubeSpecCacheKey(spec);
      // Simulate a previous run's snapshot.
      (await h.env.writeFile(
        '.fah/cube-cache/$key/cache/.cache/marker.txt',
        'hit',
      )).getOrThrow();
      // restoreIfNeeded only engages for an entry with a manifest (the
      // shape `save()` writes), so simulate the previous run's manifest.
      (await h.env.writeFile(
        '.fah/cube-cache/$key/manifest.json',
        jsonEncode({
          'key': key,
          'name': 'cached',
          'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        }),
      )).getOrThrow();
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'cached', command: const ['echo', 'hi']),
      );
      expect(code, 0);
      // Restored into the live location before the run...
      expect((await h.env.exists('.cache/marker.txt')).getOrThrow(), isTrue);
      // ...and snapshotted back with a fresh manifest after it.
      expect(
        (await h.env.exists('.fah/cube-cache/$key/manifest.json')).getOrThrow(),
        isTrue,
      );
    });

    test('a corrupt cache manifest warns but never blocks the run', () async {
      final h = _harness();
      await _writeCube(h.env, 'cached', cachePaths: '/workspace/.cache');
      final spec = (await CubeResolver.resolve(
        env: h.env,
        name: 'cached',
        homeDir: '/home/test',
      ))!;
      final key = cubeSpecCacheKey(spec);
      (await h.env.writeFile(
        '.fah/cube-cache/$key/manifest.json',
        '{garbage',
      )).getOrThrow();
      h.shell.result = const Ok(
        ShellExecResult(stdout: 'ok\n', stderr: '', exitCode: 0),
      );
      final code = await h.runner.runCommand(
        FsbRunArgs(cubeName: 'cached', command: const ['echo', 'hi']),
      );
      expect(code, 0);
      expect(h.out.toString(), 'ok\n');
      expect(h.err.toString(), startsWith('fsb: cache restore failed: '));
    });
  });

  group('FsbRunner.validateSpec', () {
    test('a valid manifest prints a summary and exits 0', () async {
      final h = _harness();
      await _writeCube(h.env, 'dev', allow: ['echo', 'git']);
      final code = await h.runner.validateSpec(
        FsbValidateArgs(path: '.fah/cubes/dev.yaml'),
      );
      expect(code, 0);
      expect(h.out.toString(), contains('name: dev'));
      expect(h.out.toString(), contains('backend: policy'));
      expect(h.out.toString(), contains('tools: 2 allow, 0 deny'));
      expect(h.out.toString(), contains('cache: disabled'));
    });

    test('an invalid manifest reports fsb: and exits 64', () async {
      final h = _harness();
      (await h.env.writeFile(
        'bad.yaml',
        'apiVersion: fa/v1\nkind: Cube\nmetadata:\n  name: x\nspec:\n'
            '  bogus: 1\n',
      )).getOrThrow();
      final code = await h.runner.validateSpec(
        FsbValidateArgs(path: 'bad.yaml'),
      );
      expect(code, 64);
      expect(h.err.toString(), startsWith('fsb: '));
      expect(h.err.toString(), contains('spec: unknown key "bogus"'));
    });

    test('a missing manifest reports fsb: and exits 64', () async {
      final h = _harness();
      final code = await h.runner.validateSpec(
        FsbValidateArgs(path: 'gone.yaml'),
      );
      expect(code, 64);
      expect(h.err.toString(), contains('fsb: cube: file not found'));
    });
  });

  group('FsbRunner.wrapCommand', () {
    test('a kernel spec stages the profile and prints the wrapper', () async {
      final h = _harness(os: 'macos');
      await _writeCube(h.env, 'kbox', backend: 'kernel');
      final spec = (await CubeResolver.resolve(
        env: h.env,
        name: 'kbox',
        homeDir: '/home/test',
      ))!;
      final code = await h.runner.wrapCommand(
        FsbWrapArgs(cubeName: 'kbox', command: const ['echo', 'hi']),
      );
      expect(code, 0);
      expect(h.out.toString(), contains('sandbox-exec'));
      expect(
        (await h.env.exists(
          '.fah/cube-profiles/${cubeSpecCacheKey(spec)}.sb',
        )).getOrThrow(),
        isTrue,
      );
    });

    test('a kernel spec on linux prints the unshare line', () async {
      final h = _harness(os: 'linux');
      await _writeCube(h.env, 'kbox', backend: 'kernel');
      final code = await h.runner.wrapCommand(
        FsbWrapArgs(cubeName: 'kbox', command: const ['echo', 'hi']),
      );
      expect(code, 0);
      expect(h.out.toString(), contains('unshare'));
    });

    test('a policy spec prints the unwrapped note', () async {
      final h = _harness();
      await _writeCube(h.env, 'pbox');
      final code = await h.runner.wrapCommand(
        FsbWrapArgs(cubeName: 'pbox', command: const ['echo', 'hi']),
      );
      expect(code, 0);
      expect(
        h.out.toString(),
        'policy mode: command runs unwrapped; enforcement is lexical only',
      );
      expect(h.shell.commands, isEmpty);
    });

    test(
      'a kernel spec without an enforcing backend degrades to the note',
      () async {
        final h = _harness(os: 'windows');
        await _writeCube(h.env, 'kbox', backend: 'kernel');
        final code = await h.runner.wrapCommand(
          FsbWrapArgs(cubeName: 'kbox', command: const ['echo', 'hi']),
        );
        expect(code, 0);
        expect(
          h.out.toString(),
          contains('policy mode: command runs unwrapped'),
        );
      },
    );
  });

  group('FsbRunner.describeBackends', () {
    test('describes every known platform once', () {
      final h = _harness(os: 'linux');
      final code = h.runner.describeBackends();
      expect(code, 0);
      expect(h.out.toString(), contains('macos: macOS sandbox-exec'));
      expect(h.out.toString(), contains('linux: Linux unshare'));
      expect(h.out.toString(), contains('windows: Windows Job Object'));
      // The current platform is already in the known list — no duplicate.
      final linuxLines = h.out
          .toString()
          .split('\n')
          .where((line) => line.startsWith('linux:'));
      expect(linuxLines, hasLength(1));
    });

    test('appends an unknown current platform', () {
      final h = _harness(os: 'freebsd');
      h.runner.describeBackends();
      expect(h.out.toString(), contains('freebsd: no-op'));
    });
  });
}
