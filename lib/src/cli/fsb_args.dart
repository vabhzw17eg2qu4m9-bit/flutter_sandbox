/// Command-line parsing for the `fsb` executable (`bin/fsb.dart`), extracted
/// as a pure, testable function: the executable maps the result to
/// usage/version output or an exit code, tests assert on it directly.
///
/// Hand-rolled like FAH's `cli_args.dart`: one linear walk over the argument
/// list, no package dependency. A `--` terminator hands everything after it
/// to the command verbatim.
library;

import '../cube/config/cube_spec.dart';

/// The usage text printed by `-h`/`--help` and after every usage error.
const String fsbHelpText = '''
usage: fsb <command> [options]

Run any console command inside a cube sandbox: a declarative profile that
clamps which commands may run, which hosts may be reached and which paths
may be touched.

commands:
  run       Run a command inside a cube (cache restore/save around it)
  wrap      Print the kernel-wrapped command line for a cube
  validate  Parse a cube manifest and print a policy summary
  backends  Describe the kernel sandbox backends

run options:
  --cube <name>         Apply <cwd>/.fah/cubes/<name>.yaml
  --cube-config <path>  Apply an explicit manifest path (wins over --cube)
  --backend <mode>      policy (default) or kernel
  --workspace <dir>     Working directory for the run (default: cwd)
  --timeout <seconds>   Wall-clock cap for the command
  -- <cmd...>           The command to run (at least one word)

Exactly one of --cube / --cube-config is required for run and wrap.
''';

/// Invalid command line: the executable prints [message] plus [help] to
/// stderr and exits with code 64 (EX_USAGE).
final class FsbUsageException implements Exception {
  /// Creates a [FsbUsageException].
  const FsbUsageException(this.message) : help = fsbHelpText;

  /// The human-readable error.
  final String message;

  /// The full usage text, printed after [message].
  final String help;

  @override
  String toString() => message;
}

/// The outcome of parsing the `fsb` argument list.
sealed class FsbArgs {
  const FsbArgs._();
}

/// `--help`/`-h` was passed: print usage and exit 0.
final class FsbHelp extends FsbArgs {
  /// Creates a [FsbHelp].
  const FsbHelp() : super._();
}

/// `--version` was passed: print the version and exit 0.
final class FsbVersion extends FsbArgs {
  /// Creates a [FsbVersion].
  const FsbVersion() : super._();
}

/// The parsed `fsb backends` command.
final class FsbBackendsArgs extends FsbArgs {
  /// Creates a [FsbBackendsArgs].
  const FsbBackendsArgs() : super._();
}

/// The parsed `fsb validate <path>` command.
final class FsbValidateArgs extends FsbArgs {
  /// Creates a [FsbValidateArgs].
  const FsbValidateArgs({required this.path}) : super._();

  /// The manifest file to parse.
  final String path;
}

/// The parsed `fsb run` command: enforce a cube around one command.
final class FsbRunArgs extends FsbArgs {
  /// Creates a [FsbRunArgs]; exactly one cube source is required.
  const FsbRunArgs({
    required this.command,
    this.cubeName,
    this.cubeConfigPath,
    this.backend,
    this.workspace,
    this.timeout,
  }) : assert(
         (cubeName == null) != (cubeConfigPath == null),
         'exactly one of cubeName and cubeConfigPath is required',
       ),
       super._();

  /// `--cube <name>`: resolve `<cwd>/.fah/cubes/<name>.yaml`.
  final String? cubeName;

  /// `--cube-config <path>`: explicit manifest path (wins over [cubeName]).
  final String? cubeConfigPath;

  /// `--backend policy|kernel`: overrides the manifest's `spec.backend`.
  final CubeBackendMode? backend;

  /// `--workspace <dir>`: working directory for the run.
  final String? workspace;

  /// `--timeout <seconds>`: wall-clock cap for the command.
  final int? timeout;

  /// The command words after `--`.
  final List<String> command;
}

/// The parsed `fsb wrap` command: print the kernel-wrapped command line.
final class FsbWrapArgs extends FsbArgs {
  /// Creates a [FsbWrapArgs]; exactly one cube source is required.
  const FsbWrapArgs({
    required this.command,
    this.cubeName,
    this.cubeConfigPath,
    this.workspace,
  }) : assert(
         (cubeName == null) != (cubeConfigPath == null),
         'exactly one of cubeName and cubeConfigPath is required',
       ),
       super._();

  /// `--cube <name>`: resolve `<cwd>/.fah/cubes/<name>.yaml`.
  final String? cubeName;

  /// `--cube-config <path>`: explicit manifest path (wins over [cubeName]).
  final String? cubeConfigPath;

  /// `--workspace <dir>`: working directory for the run.
  final String? workspace;

  /// The command words after `--`.
  final List<String> command;
}

/// Parses the `fsb` argument list.
///
/// Throws [FsbUsageException] on unknown flags, missing flag values, an
/// unknown subcommand, a missing or duplicated cube source, a bad
/// `--backend`/`--timeout` value, or a `run`/`wrap` without a command after
/// `--`.
FsbArgs parseFsbArgs(List<String> args) {
  if (args.isEmpty) throw FsbUsageException('missing subcommand');
  final arg = args.first;
  if (arg == '--help' || arg == '-h') return const FsbHelp();
  if (arg == '--version') return const FsbVersion();
  // Anything not flag-like names the subcommand; unknown `-...` arguments
  // stay an error.
  if (arg.startsWith('-')) {
    throw FsbUsageException('unknown argument: $arg');
  }
  final rest = args.sublist(1);
  return switch (arg) {
    'run' => _parseRunArgs(rest),
    'wrap' => _parseWrapArgs(rest),
    'validate' => _parseValidateArgs(rest),
    'backends' => _parseBackendsArgs(rest),
    _ => throw FsbUsageException('unknown subcommand: $arg'),
  };
}

/// Which enforce-style subcommand is being parsed: only [_EnforceVerb.run]
/// accepts `--backend`/`--timeout`; both share the cube-source flags and
/// the `--`-terminated command.
enum _EnforceVerb { run, wrap }

/// The `run`/`wrap` flag set, before the subcommand-specific result type.
typedef _EnforceFields = ({
  String? cubeName,
  String? cubeConfigPath,
  CubeBackendMode? backend,
  String? workspace,
  int? timeout,
  List<String> command,
});

/// Mutable twin of [_EnforceFields]: [_parseEnforceFields] fills fields in
/// while walking the flags; [_finishEnforceFields] validates and freezes
/// the result into the record.
final class _EnforceState {
  String? cubeName;
  String? cubeConfigPath;
  CubeBackendMode? backend;
  String? workspace;
  int? timeout;
  List<String>? command;

  /// Applies the flag at index [i] and returns the index of its consumed
  /// value; anything that is not a known flag — including a bare command
  /// word before `--` — is a usage error naming [verb].
  int applyFlag(List<String> args, int i, _EnforceVerb verb) {
    final arg = args[i];
    switch (arg) {
      case '--cube':
        _requireValue(args, arg, i);
        _requireNotDuplicate(arg, cubeName);
        cubeName = args[i + 1];
      case '--cube-config':
        _requireValue(args, arg, i);
        _requireNotDuplicate(arg, cubeConfigPath);
        cubeConfigPath = args[i + 1];
      case '--backend' when verb == _EnforceVerb.run:
        _requireValue(args, arg, i);
        backend = _parseBackend(args[i + 1]);
      case '--workspace':
        _requireValue(args, arg, i);
        workspace = args[i + 1];
      case '--timeout' when verb == _EnforceVerb.run:
        _requireValue(args, arg, i);
        timeout = _parseTimeout(args[i + 1]);
      default:
        throw FsbUsageException(
          arg.startsWith('-')
              ? 'unknown argument: $arg'
              : '${verb.name} requires a command after --',
        );
    }
    return i + 1;
  }
}

FsbRunArgs _parseRunArgs(List<String> args) {
  final fields = _parseEnforceFields(args, _EnforceVerb.run);
  return FsbRunArgs(
    command: fields.command,
    cubeName: fields.cubeName,
    cubeConfigPath: fields.cubeConfigPath,
    backend: fields.backend,
    workspace: fields.workspace,
    timeout: fields.timeout,
  );
}

FsbWrapArgs _parseWrapArgs(List<String> args) {
  final fields = _parseEnforceFields(args, _EnforceVerb.wrap);
  return FsbWrapArgs(
    command: fields.command,
    cubeName: fields.cubeName,
    cubeConfigPath: fields.cubeConfigPath,
    workspace: fields.workspace,
  );
}

/// The shared `run`/`wrap` grammar: `[flags] -- command...` with exactly
/// one cube source; [verb] selects the accepted flags and the wording of
/// usage errors.
///
/// Throws [FsbUsageException] on unknown flags, missing flag values, a
/// duplicated or missing cube source, a bad `--backend`/`--timeout` value,
/// or a missing/empty command (a bare word before `--` reads as the
/// missing-separator mistake and names [verb]).
_EnforceFields _parseEnforceFields(List<String> args, _EnforceVerb verb) {
  final state = _EnforceState();
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') {
      // Everything after `--` is the command verbatim — dash-prefixed
      // words included.
      state.command = args.sublist(i + 1);
      break;
    }
    i = state.applyFlag(args, i, verb);
  }
  return _finishEnforceFields(state, verb);
}

/// Validates the accumulated fields and freezes them into the record.
_EnforceFields _finishEnforceFields(_EnforceState state, _EnforceVerb verb) {
  _requireCubeSource(state.cubeName, state.cubeConfigPath);
  final command = state.command;
  if (command == null || command.isEmpty) {
    throw FsbUsageException('${verb.name} requires a command after --');
  }
  return (
    cubeName: state.cubeName,
    cubeConfigPath: state.cubeConfigPath,
    backend: state.backend,
    workspace: state.workspace,
    timeout: state.timeout,
    command: command,
  );
}

/// Rejects a second occurrence of a once-only cube-source flag.
void _requireNotDuplicate(String arg, Object? existing) {
  if (existing != null) {
    throw FsbUsageException(
      'duplicate cube source: $arg '
      '(exactly one of --cube or --cube-config)',
    );
  }
}

FsbValidateArgs _parseValidateArgs(List<String> args) {
  if (args.isEmpty) {
    throw FsbUsageException('validate requires a manifest path');
  }
  if (args.length > 1) {
    throw FsbUsageException(
      'validate takes exactly one manifest path, got ${args.length}',
    );
  }
  return FsbValidateArgs(path: args.single);
}

FsbBackendsArgs _parseBackendsArgs(List<String> args) {
  if (args.isNotEmpty) {
    throw FsbUsageException('backends takes no arguments');
  }
  return const FsbBackendsArgs();
}

/// The value following a value-taking flag at index [i], or a usage error.
void _requireValue(List<String> args, String arg, int i) {
  if (i + 1 >= args.length) {
    throw FsbUsageException('$arg requires a value');
  }
}

void _requireCubeSource(String? cubeName, String? cubeConfigPath) {
  if (cubeName != null && cubeConfigPath != null) {
    throw FsbUsageException('cannot combine --cube and --cube-config');
  }
  if (cubeName == null && cubeConfigPath == null) {
    throw FsbUsageException(
      'exactly one of --cube or --cube-config is required',
    );
  }
}

CubeBackendMode _parseBackend(String value) => switch (value) {
  'policy' => CubeBackendMode.policy,
  'kernel' => CubeBackendMode.kernel,
  _ => throw FsbUsageException(
    'unknown backend: $value (use policy or kernel)',
  ),
};

int _parseTimeout(String value) {
  final seconds = int.tryParse(value);
  if (seconds == null || seconds <= 0) {
    throw FsbUsageException(
      '--timeout requires a positive integer number of seconds, got $value',
    );
  }
  return seconds;
}
