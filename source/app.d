import std.stdio;
import std.array;
import std.getopt;
import std.exception;

struct Document {
  ParsingState st = ParsingState.Root;
  bool escape = false;
  bool flushOnEveryLine = false;
  bool printLineNumbers = false;
  ubyte[] filename = null;
  size_t lineNumber = 1;
  Appender!(Segment[]) segs = appender!(Segment[]);
}

enum ParsingState {
  Root,

  ObjWantingKey, ObjReadingKey,

  ObjWantingValue, ObjReadingStringValue, ObjReadingBareValue,

  ArrWantingValue, ArrReadingStringValue, ArrReadingBareValue,
}

enum SegmentType {JsonObject, JsonArray};

struct Segment {
  SegmentType type;
  union {
    int idx;
    ubyte[] key;
  }
}

struct Options {
  bool withFilename = false;
  bool noFilename = false;
  bool withLineNumbers = false;
}

void main(string[] args) {

  auto opts = Options();

  auto helpInfo = getopt(
    args, config.passThrough, config.bundling,
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

void process(string[] files, Options opts) {

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

void processStdin(bool withFilename, bool withLineNumbers) {
  Document doc = { 
    flushOnEveryLine: true,
    printLineNumbers: withLineNumbers
  };

  if (withFilename) {
    doc.filename = cast(ubyte[])"-";
  }

	foreach (const ubyte[] buffer; stdin.chunks(1)) {
    if (buffer[0] == cast(ubyte)'\n') {
      doc.lineNumber++;
    }
    feed(doc, buffer[0]);
  }

  flush();
}

void processFile(string filename, bool withFilename, bool withLineNumbers) {
  try {
    auto f = File(filename, "r");

    Document doc = {
      printLineNumbers: withLineNumbers
    };

    if (withFilename) {
      doc.filename = cast(ubyte[])filename;
    }

    foreach (const ubyte[] buffer; f.chunks(4096)) {
      for (size_t i=0; i<buffer.length; i++) {
        if (buffer[i] == cast(ubyte)'\n') {
          doc.lineNumber++;
        }
        feed(doc, buffer[i]);
      }
    }

    flush();
  }
  catch (ErrnoException e) {
    writeln("Unable to read file: ", filename);
  }
}

ubyte[4096] writeBuffer;
size_t writeBufferLength = 0;
void flush() {
  stdout.rawWrite(writeBuffer[0..writeBufferLength]);
  writeBufferLength = 0;
}

void printByte(ubyte b) {
  if (writeBufferLength == writeBuffer.length) {
    flush();
  }
  writeBuffer[writeBufferLength++] = b;
}

void printByteSlice(const ubyte[] buffer) {
  foreach (ubyte b; buffer) {
    printByte(b);
  }
}

void printNumber(size_t n) {
  size_t numDigits = 0;
  ubyte[20] buf; // <-- check to see how large this actually needs to be TODO!
  if (n == 0) {
    printByte(cast(ubyte)'0');
    return;
  }
  while (n > 0) {
    buf[numDigits++] = cast(ubyte)'0' + (n%10);
    n /= 10;
  }
  for (size_t i=1; i<=numDigits; i++) {
    printByte(buf[numDigits-i]);
  }
}

void printNewline(bool doFlush) {
  printByte(cast(ubyte)'\n');
  if (doFlush) {
    flush();
  }
}

void feed(ref Document doc, ubyte tok) {
  final switch (doc.st) {
    case ParsingState.Root:
      return root(doc, tok);

    case ParsingState.ObjWantingKey:
      return objWantingKey(doc, tok);

    case ParsingState.ObjReadingKey:
      return objReadingKey(doc, tok);

    case ParsingState.ObjWantingValue:
      return objWantingValue(doc, tok);

    case ParsingState.ObjReadingStringValue:
      return readingStringValue(doc, tok, ParsingState.ObjWantingKey);

    case ParsingState.ObjReadingBareValue:
      return readingBareValue(doc, tok, ParsingState.ObjWantingKey);

    case ParsingState.ArrWantingValue:
      return arrWantingValue(doc, tok);

    case ParsingState.ArrReadingStringValue:
      return readingStringValue(doc, tok, ParsingState.ArrWantingValue);

    case ParsingState.ArrReadingBareValue:
      return readingBareValue(doc, tok, ParsingState.ArrWantingValue);
  }
}

Segment objectSegment() {
  Segment s;
  s.type = SegmentType.JsonObject;
  s.key = new ubyte[32];
  return s;
}

Segment arraySegment() {
  Segment s;
  s.type = SegmentType.JsonArray;
  s.idx = 0;
  return s;
}

bool isWhite(ubyte b) {
  return b <= cast(ubyte)' ';
}

ref S last(S)(ref Appender!(S[]) app) {
  return app[][app[].length-1];
}

void pop(S)(ref Appender!(S[]) app) {
  app.shrinkTo(app[].length-1);
}

void writeFullKey(const Document doc) {
  if (doc.filename !is null) {
    printByteSlice(doc.filename);
    printByte(':');
  }
  if (doc.printLineNumbers) {
    printNumber(doc.lineNumber);
    printByte(':');
  }

  foreach (i, Segment s; doc.segs[]) {
    if ( i > 0 ) {
      printByte(cast(ubyte)'.');
    }
    final switch (s.type) {
      case SegmentType.JsonObject:
        printByteSlice(s.key);
        break;
      case SegmentType.JsonArray:
        printNumber(s.idx-1);
        break;
    }
  }
 
  printByte(' ');
  printByte(' ');
}

void popSegment(ref Document doc) {
  doc.segs.pop();
  if (doc.segs[].length == 0) {
    doc.st = ParsingState.Root;
    return;
  }

  final switch(doc.segs.last.type) {
    case SegmentType.JsonObject:
      doc.st = ParsingState.ObjWantingKey;
      return;
    case SegmentType.JsonArray:
      doc.st = ParsingState.ArrWantingValue;
      return;
  }
}

// State parsing functions

void root(ref Document doc, ubyte tok) {
  if ( tok == cast(ubyte)'{' ) {
    doc.st = ParsingState.ObjWantingKey;
    doc.segs.put(objectSegment());
    return;
  }

  if ( tok == cast(ubyte)'[' ) {
    doc.st = ParsingState.ArrWantingValue;
    doc.segs.put(arraySegment());
    return;
  }

  // TODO: Include this if we want interspersed json (as in a log file or something)
  //put(cast(char)tok);
}

void objWantingKey(ref Document doc, ubyte tok) {
  // {     "some"   : "thing" }
  //  1     2
  // {"some":"thing"  , "else": true }
  //                1    2
  // {"some":"thing"   }
  //                1  2
  if (isWhite(tok) || tok == cast(ubyte)',') return;

  if (tok == cast(ubyte)'"') {
    doc.st = ParsingState.ObjReadingKey;
    doc.segs.last.key.length = 0;
    return;
  }

  if (tok == cast(ubyte)'}') {
    popSegment(doc);
    return;
  }

  doc.st = ParsingState.Root;
  doc.segs.clear();
  doc.escape = false;
}

void objReadingKey(ref Document doc, ubyte tok) {
  if (doc.escape) {
    doc.escape = false;
    doc.segs.last.key ~= tok;
    return;
  }

  if (tok == cast(ubyte)'\\') {
    doc.escape = true;
    doc.segs.last.key ~= tok;
    return;
  }

  if (tok == cast(ubyte)'"') {
    doc.st = ParsingState.ObjWantingValue;
    return;
  }

  doc.segs.last.key ~= tok;
}

void objWantingValue(ref Document doc, ubyte tok) {
  //write("TODO, but with key=", cast(string)doc.segs.last.data.key[]);
  if (isWhite(tok) || tok == cast(ubyte)':') return;

  if (tok == cast(ubyte)'{' ) {
    doc.st = ParsingState.ObjWantingKey;
    doc.segs.put(objectSegment());
    return;
  }
  
  if (tok == cast(ubyte)'[' ) {
    doc.st = ParsingState.ArrWantingValue;
    doc.segs.put(arraySegment());
    return;
  }

  if (tok == cast(ubyte)'"' ) {
    writeFullKey(doc);
    printByte(cast(ubyte)'"');
    doc.st = ParsingState.ObjReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'. Don't really care though!

  writeFullKey(doc);
  printByte(tok);
  doc.st = ParsingState.ObjReadingBareValue;
}

void arrWantingValue(ref Document doc, ubyte tok) {
  if (isWhite(tok) || tok == cast(ubyte)',') return;

  doc.segs.last.idx++;
  
  if (tok == cast(ubyte)'{' ) {
    doc.st = ParsingState.ObjWantingKey;
    doc.segs.put(objectSegment());
    return;
  }

  if (tok == cast(ubyte)'[' ) {
    doc.st = ParsingState.ArrWantingValue;
    doc.segs.put(arraySegment());
    return;
  }
  
  if (tok == cast(ubyte)']' ) {
    popSegment(doc);
    return;
  }

  if (tok == cast(ubyte)'"' ) {
    writeFullKey(doc);
    printByte(cast(ubyte)'"');
    doc.st = ParsingState.ArrReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'

  writeFullKey(doc);
  printByte(tok);
  doc.st = ParsingState.ArrReadingBareValue;
}

void readingStringValue(ref Document doc, ubyte tok, ParsingState nextState) {
  if (doc.escape) {
    printByte(tok);
    doc.escape = false;
    return;
  }

  if ( tok == cast(ubyte)'\\' ) {
    doc.escape = true;
    printByte(cast(ubyte)'\\');
    return;
  }

  if ( tok == cast(ubyte)'"' ) {
    doc.st = nextState;
    printByte(cast(ubyte)'"');
    printNewline(doc.flushOnEveryLine);
    return;
  }

  printByte(tok);
}

void readingBareValue(ref Document doc, ubyte tok, ParsingState nextState) {
  if (tok == cast(ubyte)']') {
    // todo: if nextState != ParsingState.ArrWantingValue we have bad JSON
    printNewline(doc.flushOnEveryLine);
    popSegment(doc);
    return;
  }

  if (tok == cast(ubyte)'}') {
    // todo: if nextState != ObjWantingKey we have bad json
    printNewline(doc.flushOnEveryLine);
    popSegment(doc);
    return;
  }

  if ( isWhite(tok) || tok == cast(ubyte)',' ) {
    printNewline(doc.flushOnEveryLine);
    doc.st = nextState;
    return;
  }

  printByte(tok);
}

