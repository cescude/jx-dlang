import std.stdio;
import std.array;
import std.getopt;

import json : processStdin, processFile;

struct Options {
  bool withFilename = false;
  bool noFilename = false;
  bool withLineNumbers = false;
}

void main(string[] args) {

  auto opts = Options();

  auto helpInfo = getopt(
    args, config.passThrough, config.bundling, config.caseSensitive,
    "with-filename|H", "Print file name with output lines.", &opts.withFilename,
    "no-filename", "Suppress the file name prefix on output.", &opts.noFilename,
    "line-number|n", "Print line number with output lines.", &opts.withLineNumbers
  );

  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: jx [FILE]...",
      helpInfo.options
    );
    return;
  }

  process(args[1..$], opts);
}

void process(string[] files, const Options opts) {

  if (files.length == 0) {
    processStdin(opts.withFilename, opts.withLineNumbers);
  }
  else if (files.length == 1) {
    processFile(files[0], opts.withFilename, opts.withLineNumbers);
  }
  else {
    foreach (string file; files) {
      processFile(file, !opts.noFilename, opts.withLineNumbers);
    }
  }
}

