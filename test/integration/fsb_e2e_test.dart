@TestOn('vm')
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('fsb end-to-end', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('fsb_e2e_');
    });

    tearDown(() {
      workspace.deleteSync(recursive: true);
    });

    /// Writes a minimal cube manifest into the temp workspace and returns
    /// its path.
    String writeCube(String name, {required List<String> allow}) {
      final file = File('${workspace.path}/.fah/cubes/$name.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
apiVersion: fa/v1
kind: Cube
metadata:
  name: $name
spec:
  tools:
    allow: [${allow.join(', ')}]
''');
      return file.path;
    }

    /// Spawns the real `fsb` binary over the package checkout.
    Future<ProcessResult> runFsb(List<String> args) =>
        Process.run('dart', ['run', 'bin/fsb.dart', ...args]);

    test('allowed command: echo runs and its output reaches stdout', () async {
      final cube = writeCube('echo-box', allow: ['/bin/echo']);
      final result = await runFsb([
        'run',
        '--cube-config',
        cube,
        '--',
        '/bin/echo',
        'hi',
      ]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('hi'));
    });

    test('denied command: rm is refused with the fa_cube note', () async {
      final cube = writeCube('echo-box', allow: ['/bin/echo']);
      final result = await runFsb([
        'run',
        '--cube-config',
        cube,
        '--',
        'rm',
        '-rf',
        './junk',
      ]);
      expect(result.exitCode, 127);
      expect(result.stderr, contains('fa_cube['));
      expect(
        result.stderr,
        contains("command 'rm' not in cube 'echo-box' allowlist"),
      );
    });

    test('a missing manifest fails closed with exit 64', () async {
      final result = await runFsb([
        'run',
        '--cube-config',
        '${workspace.path}/gone.yaml',
        '--',
        '/bin/echo',
        'hi',
      ]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('fsb: cube: file not found'));
    });

    test('validate prints a summary and exits 0', () async {
      final cube = writeCube('echo-box', allow: ['/bin/echo']);
      final result = await runFsb(['validate', cube]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('name: echo-box'));
      expect(result.stdout, contains('tools: 1 allow, 0 deny'));
    });
  });
}
