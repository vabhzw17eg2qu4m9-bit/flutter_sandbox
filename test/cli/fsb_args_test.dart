import 'package:flutter_sandbox/src/cube/config/cube_spec.dart';
import 'package:flutter_sandbox/src/cli/fsb_args.dart';
import 'package:test/test.dart';

void main() {
  group('parseFsbArgs', () {
    test('no args is a usage error', () {
      expect(
        () => parseFsbArgs(const []),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('missing subcommand'),
          ),
        ),
      );
    });

    test('--version requests the version', () {
      expect(parseFsbArgs(const ['--version']), isA<FsbVersion>());
    });

    test('--help and -h request usage', () {
      expect(parseFsbArgs(const ['--help']), isA<FsbHelp>());
      expect(parseFsbArgs(const ['-h']), isA<FsbHelp>());
    });

    test('run parses the cube name and command after --', () {
      final args =
          parseFsbArgs(const ['run', '--cube', 'dev', '--', 'echo', 'hi'])
              as FsbRunArgs;
      expect(args.cubeName, 'dev');
      expect(args.cubeConfigPath, isNull);
      expect(args.command, ['echo', 'hi']);
      expect(args.backend, isNull);
      expect(args.workspace, isNull);
      expect(args.timeout, isNull);
    });

    test('--cube-config sets the manifest path', () {
      final args =
          parseFsbArgs(const [
                'run',
                '--cube-config',
                '~/cubes/dev.yaml',
                '--',
                'ls',
              ])
              as FsbRunArgs;
      expect(args.cubeConfigPath, '~/cubes/dev.yaml');
      expect(args.cubeName, isNull);
      expect(args.command, ['ls']);
    });

    test('run parses every flag', () {
      final args =
          parseFsbArgs(const [
                'run',
                '--cube-config',
                '/c/dev.yaml',
                '--backend',
                'kernel',
                '--workspace',
                '/tmp/w',
                '--timeout',
                '30',
                '--',
                'git',
                'status',
              ])
              as FsbRunArgs;
      expect(args.cubeConfigPath, '/c/dev.yaml');
      expect(args.backend, CubeBackendMode.kernel);
      expect(args.workspace, '/tmp/w');
      expect(args.timeout, 30);
      expect(args.command, ['git', 'status']);
    });

    test('--backend policy parses', () {
      final args =
          parseFsbArgs(const [
                'run',
                '--cube',
                'dev',
                '--backend',
                'policy',
                '--',
                'x',
              ])
              as FsbRunArgs;
      expect(args.backend, CubeBackendMode.policy);
    });

    test('an unknown backend is an error', () {
      expect(
        () => parseFsbArgs(const [
          'run',
          '--cube',
          'dev',
          '--backend',
          'bogus',
          '--',
          'x',
        ]),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('unknown backend: bogus'),
          ),
        ),
      );
    });

    test('--timeout requires a positive integer number of seconds', () {
      for (final bad in const ['abc', '0', '-5', '1.5']) {
        expect(
          () => parseFsbArgs(
            const ['run', '--cube', 'dev', '--timeout'] +
                [bad] +
                const ['--', 'x'],
          ),
          throwsA(isA<FsbUsageException>()),
          reason: '--timeout $bad should be rejected',
        );
      }
    });

    test('a missing flag value is an error', () {
      expect(
        () => parseFsbArgs(const ['run', '--cube']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('--cube requires a value'),
          ),
        ),
      );
      expect(
        () => parseFsbArgs(const ['run', '--cube', 'dev', '--workspace']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('--workspace requires a value'),
          ),
        ),
      );
    });

    test('run without -- is an error', () {
      expect(
        () => parseFsbArgs(const ['run', '--cube', 'dev', 'echo', 'hi']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('run requires a command after --'),
          ),
        ),
      );
    });

    test('run with an empty command after -- is an error', () {
      expect(
        () => parseFsbArgs(const ['run', '--cube', 'dev', '--']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('run requires a command after --'),
          ),
        ),
      );
    });

    test('run without --cube or --cube-config is an error', () {
      expect(
        () => parseFsbArgs(const ['run', '--', 'echo', 'hi']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('exactly one of --cube or --cube-config is required'),
          ),
        ),
      );
    });

    test('run with both --cube and --cube-config is an error', () {
      expect(
        () => parseFsbArgs(const [
          'run',
          '--cube',
          'dev',
          '--cube-config',
          '/c/dev.yaml',
          '--',
          'x',
        ]),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('cannot combine --cube and --cube-config'),
          ),
        ),
      );
    });

    test('a duplicated --cube is an error', () {
      expect(
        () => parseFsbArgs(const [
          'run',
          '--cube',
          'a',
          '--cube',
          'b',
          '--',
          'x',
        ]),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('duplicate cube source'),
          ),
        ),
      );
    });

    test('command words after -- keep dash-prefixed flags verbatim', () {
      final args =
          parseFsbArgs(const [
                'run',
                '--cube',
                'dev',
                '--',
                'curl',
                '-I',
                'https://x.example',
              ])
              as FsbRunArgs;
      expect(args.command, ['curl', '-I', 'https://x.example']);
    });

    test('unknown flag fails', () {
      expect(
        () => parseFsbArgs(const ['run', '--bogus', 'x', '--', 'y']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('unknown argument: --bogus'),
          ),
        ),
      );
    });

    test('unknown subcommand fails', () {
      expect(
        () => parseFsbArgs(const ['frobnicate']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('unknown subcommand: frobnicate'),
          ),
        ),
      );
    });

    test('validate requires exactly one path', () {
      expect(
        () => parseFsbArgs(const ['validate']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('validate requires a manifest path'),
          ),
        ),
      );
      expect(
        () => parseFsbArgs(const ['validate', 'a.yaml', 'b.yaml']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('validate takes exactly one manifest path'),
          ),
        ),
      );
      final args =
          parseFsbArgs(const ['validate', '.fah/cubes/dev.yaml'])
              as FsbValidateArgs;
      expect(args.path, '.fah/cubes/dev.yaml');
    });

    test('wrap parses flags and command', () {
      final args =
          parseFsbArgs(const [
                'wrap',
                '--cube',
                'dev',
                '--workspace',
                '/tmp/w',
                '--',
                'echo',
                'hi',
              ])
              as FsbWrapArgs;
      expect(args.cubeName, 'dev');
      expect(args.workspace, '/tmp/w');
      expect(args.command, ['echo', 'hi']);
    });

    test('wrap rejects run-only flags', () {
      expect(
        () => parseFsbArgs(const [
          'wrap',
          '--cube',
          'dev',
          '--backend',
          'kernel',
          '--',
          'x',
        ]),
        throwsA(isA<FsbUsageException>()),
      );
    });

    test('backends takes no arguments', () {
      expect(parseFsbArgs(const ['backends']), isA<FsbBackendsArgs>());
      expect(
        () => parseFsbArgs(const ['backends', 'extra']),
        throwsA(
          isA<FsbUsageException>().having(
            (e) => e.message,
            'message',
            contains('backends takes no arguments'),
          ),
        ),
      );
    });

    test('a usage error carries the help text', () {
      final error = FsbUsageException('boom');
      expect(error.help, fsbHelpText);
      expect(error.help, contains('usage: fsb'));
      expect(error.toString(), 'boom');
    });
  });
}
