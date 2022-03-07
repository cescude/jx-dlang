module json;

import std.stdio;
import std.array;

struct DocState {
  ParsingState st = ParsingState.Root;
  bool escape = false;
  immutable bool flushOnEveryLine = false;
  immutable bool printLineNumbers = false;
  const ubyte[] filename = null;
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
    size_t idx;
    ubyte[] key;
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

  // No reason to deal with negatives

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

void printFullKey(const DocState doc) {
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

void feed(ref DocState doc, ubyte tok) {
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

void finish() {
  flush();
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

void popSegment(ref DocState doc) {
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

void root(ref DocState doc, ubyte tok) {
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

void objWantingKey(ref DocState doc, ubyte tok) {
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

void objReadingKey(ref DocState doc, ubyte tok) {
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

void objWantingValue(ref DocState doc, ubyte tok) {
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
    printFullKey(doc);
    printByte(cast(ubyte)'"');
    doc.st = ParsingState.ObjReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'. Don't really care though!

  printFullKey(doc);
  printByte(tok);
  doc.st = ParsingState.ObjReadingBareValue;
}

void arrWantingValue(ref DocState doc, ubyte tok) {
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
    printFullKey(doc);
    printByte(cast(ubyte)'"');
    doc.st = ParsingState.ArrReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'

  printFullKey(doc);
  printByte(tok);
  doc.st = ParsingState.ArrReadingBareValue;
}

void readingStringValue(ref DocState doc, ubyte tok, ParsingState nextState) {
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

void readingBareValue(ref DocState doc, ubyte tok, ParsingState nextState) {
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
