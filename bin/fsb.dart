/// The `fsb` executable: run any console command inside a cube sandbox.
///
/// Thin on purpose — argument parsing lives in `lib/src/cli/fsb_args.dart`,
/// the execution engine in `lib/src/cli/sandbox_runner.dart`; this file owns
/// only process-level concerns (dart:io, the real platform environment).
library;

import 'dart:io';

import 'package:flutter_sandbox/io.dart';
import 'package:flutter_sandbox/src/cli/fsb_args.dart';
import 'package:flutter_sandbox/src/cli/sandbox_runner.dart';

// Keep in sync with `version:` in pubspec.yaml.
const fsbVersion = '0.1.0';

Future<void> main(List<String> args) async {
  final FsbArgs parsed;
  try {
    parsed = parseFsbArgs(args);
  } on FsbUsageException catch (error) {
    stderr
      ..writeln('fsb: ${error.message}')
      ..write(error.help);
    exitCode = 64;
    return;
  }
  switch (parsed) {
    case FsbHelp():
      stdout.write(fsbHelpText);
    case FsbVersion():
      stdout.writeln(fsbVersion);
    case FsbBackendsArgs():
      exitCode = _runner(null).describeBackends();
    case FsbValidateArgs():
      exitCode = await _runner(null).validateSpec(parsed);
    case FsbRunArgs(:final workspace):
      exitCode = await _runner(workspace).runCommand(parsed);
    case FsbWrapArgs(:final workspace):
      exitCode = await _runner(workspace).wrapCommand(parsed);
  }
}

/// The runner over the real process environment, rooted at [workspace]
/// (null = the process cwd).
FsbRunner _runner(String? workspace) => FsbRunner(
  env: LocalExecutionEnv(cwd: workspace ?? Directory.current.path),
  homeDir: Platform.environment['HOME'],
  os: Platform.operatingSystem,
  writeStdout: stdout.write,
  writeStderr: stderr.write,
);
