import std.stdio;
import std.array;
import std.getopt;
import std.exception;

struct Document {
  ParsingState st = ParsingState.Root;
  bool escape = false;
  bool flushOnEveryLine = false;
  ubyte[] filename = null;
  Appender!(Segment[]) segs = appender!(Segment[]);
}

enum ParsingState {
  Root, 
  ObjWantingKey, ObjReadingKey, ObjWantingValue, ObjReadingStringValue, ObjReadingBareValue,
  ArrWantingValue, ArrReadingStringValue, ArrReadingBareValue,
}

enum SegmentType {JsonObject, JsonArray};

struct Segment {
  SegmentType type;
  union {
    int idx;
    Appender!(ubyte[]) key;
  }
}

void main(string[] args) {

  auto helpInfo = getopt(args, config.passThrough);
  if (helpInfo.helpWanted) {
    defaultGetoptPrinter(
      "Usage: jx [FILE]...",
      helpInfo.options
    );
    return;
  }

  process(args[1..$]);
}

void process(string[] files) {

  if (files.length == 0) {
    processStdin();
    return;
  }

  foreach (string file; files) {
    if (files.length > 1) {
      // TODO: WOuld be better to prefix each line w/ the name!
      //writeln("==> ", file, " <==");
    }
    processFile(file, files.length > 1);
  }
}

void processStdin() {
  Document doc = {};
  doc.flushOnEveryLine = true;
	foreach (const ubyte[] buffer; stdin.chunks(1)) {
    feed(doc, buffer[0]);
  }
  flush();
}

void processFile(string filename, bool includeFilename) {
  try {
    auto f = File(filename, "r");

    Document doc = {};
    if (includeFilename) {
      doc.filename = cast(ubyte[])filename;
    }
    foreach (const ubyte[] buffer; f.chunks(4096)) {
      for (size_t i=0; i<buffer.length; i++) {
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
  s.key = appender!(ubyte[]);
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

  foreach (i, Segment s; doc.segs[]) {
    if ( i > 0 ) {
      printByte(46);
    }
    final switch (s.type) {
      case SegmentType.JsonObject:
        printByteSlice(s.key[]);
        break;
      case SegmentType.JsonArray:
        printNumber(s.idx-1);
        break;
    }
  }
  //put("  ");
  printByte(32); printByte(32);
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
    doc.segs.last.key.clear();
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
    doc.segs.last.key.put(tok);
    doc.escape = false;
    return;
  }

  if (tok == cast(ubyte)'\\') {
    doc.escape = true;
    doc.segs.last.key.put(tok);
    return;
  }

  if (tok == cast(ubyte)'"') {
    doc.st = ParsingState.ObjWantingValue;
    return;
  }

  doc.segs.last.key.put(tok);
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

