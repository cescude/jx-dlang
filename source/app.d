import std.stdio;
import std.array;
import std.getopt;
import std.exception;

import json : DocState, feed, finish;

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

  finish();
}

void processStdin(bool withFilename, bool withLineNumbers) {
  DocState doc = { 
    flushOnEveryLine: true,
    printLineNumbers: withLineNumbers,
    filename: withFilename ? cast(ubyte[])"-" : null
  };

  foreach (const ubyte[] buffer; stdin.chunks(1)) {
    if (buffer[0] == cast(ubyte)'\n') {
      doc.lineNumber++;
    }
    doc.feed(buffer[0]);
  }
}

void processFile(string filename, bool withFilename, bool withLineNumbers) {
  try {
    auto f = File(filename, "r");

    DocState doc = {
      printLineNumbers: withLineNumbers,
      filename: withFilename ? cast(ubyte[])filename : null
    };

    foreach (const ubyte[] buffer; f.chunks(4096)) {
      for (size_t i=0; i<buffer.length; i++) {
        if (buffer[i] == cast(ubyte)'\n') {
          doc.lineNumber++;
        }
        doc.feed(buffer[i]);
      }
    }
  }
  catch (ErrnoException e) {
    writeln("Unable to read file: ", filename);
  }
}

