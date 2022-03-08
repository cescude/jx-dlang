module json;

import std.stdio;
import std.array;

ParsingState st;
bool flushOnEveryLine;
bool printLineNumbers;
ubyte[] filename;
size_t lineNumber;
Appender!(Segment[]) segs;

void init(bool optFlushOnEveryLine, bool optPrintLineNumbers, ubyte[] optFilename) {
  st = ParsingState.Root;
  flushOnEveryLine = optFlushOnEveryLine;
  printLineNumbers = optPrintLineNumbers;
  filename = optFilename;
  lineNumber = 1;
  segs = appender!(Segment[]);
}

enum ParsingState {
  Root,
  ObjWantingKey, 
  ObjReadingKey, ObjReadingKeyEscaped,
  ObjWantingValue, 
  ObjReadingStringValue, ObjReadingStringValueEscaped, ObjReadingBareValue,
  ArrWantingValue, 
  ArrReadingStringValue, ArrReadingStringValueEscaped, ArrReadingBareValue,
}

immutable void function(ubyte)[] table = [
  &root,
  &objWantingKey,
  &objReadingKey,
  &objReadingKeyEscaped,
  &objWantingValue,
  &objReadingStringValue,
  &objReadingStringValueEscaped,
  &objReadingBareValue,
  &arrWantingValue,
  &arrReadingStringValue,
  &arrReadingStringValueEscaped,
  &arrReadingBareValue
];

enum SegmentType {JsonObject, JsonArray};

struct Segment {
  SegmentType type;
  union {
    size_t idx;
    Appender!(ubyte[]) key;
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

void printFullKey() {
  if (filename !is null) {
    printByteSlice(filename);
    printByte(':');
  }
  if (printLineNumbers) {
    printNumber(lineNumber);
    printByte(':');
  }

  foreach (i, Segment s; segs[]) {
    if ( i > 0 ) {
      printByte(cast(ubyte)'.');
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
 
  printByte(' ');
  printByte(' ');
}

void feed(ubyte tok) {
  if (tok == cast(ubyte)'\n') {
    lineNumber++;
  }
  table[st](tok);
}

void finish() {
  flush();
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

void popSegment() {
  segs.pop();
  if (segs[].length == 0) {
    st = ParsingState.Root;
    return;
  }

  final switch(segs.last.type) {
    case SegmentType.JsonObject:
      st = ParsingState.ObjWantingKey;
      return;
    case SegmentType.JsonArray:
      st = ParsingState.ArrWantingValue;
      return;
  }
}

// State parsing functions

void root(ubyte tok) {
  if ( tok == cast(ubyte)'{' ) {
    st = ParsingState.ObjWantingKey;
    segs.put(objectSegment());
    return;
  }

  if ( tok == cast(ubyte)'[' ) {
    st = ParsingState.ArrWantingValue;
    segs.put(arraySegment());
    return;
  }

  // TODO: Include this if we want interspersed json (as in a log file or something)
  //put(cast(char)tok);
}

void objWantingKey(ubyte tok) {
  // {     "some"   : "thing" }
  //  1     2
  // {"some":"thing"  , "else": true }
  //                1    2
  // {"some":"thing"   }
  //                1  2
  if (isWhite(tok) || tok == cast(ubyte)',') return;

  if (tok == cast(ubyte)'"') {
    st = ParsingState.ObjReadingKey;
    segs.last.key.clear();
    return;
  }

  if (tok == cast(ubyte)'}') {
    popSegment();
    return;
  }

  st = ParsingState.Root;
  segs.clear();
}

void objReadingKey(ubyte tok) {
  if (tok == cast(ubyte)'\\') {
    segs.last.key.put(tok);
    st = ParsingState.ObjReadingKeyEscaped;
    return;
  }

  if (tok == cast(ubyte)'"') {
    st = ParsingState.ObjWantingValue;
    return;
  }

  segs.last.key.put(tok); 
}

void objReadingKeyEscaped(ubyte tok) {
  segs.last.key.put(tok);
  st = ParsingState.ObjReadingKey;
}

void objWantingValue(ubyte tok) {
  if (isWhite(tok) || tok == cast(ubyte)':') return;

  if (tok == cast(ubyte)'{' ) {
    st = ParsingState.ObjWantingKey;
    segs.put(objectSegment());
    return;
  }
  
  if (tok == cast(ubyte)'[' ) {
    st = ParsingState.ArrWantingValue;
    segs.put(arraySegment());
    return;
  }

  if (tok == cast(ubyte)'"' ) {
    printFullKey();
    printByte(cast(ubyte)'"');
    st = ParsingState.ObjReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'. Don't really care though!

  printFullKey();
  printByte(tok);
  st = ParsingState.ObjReadingBareValue;
}

void arrWantingValue(ubyte tok) {
  if (isWhite(tok) || tok == cast(ubyte)',') return;

  segs.last.idx++;
  
  if (tok == cast(ubyte)'{' ) {
    st = ParsingState.ObjWantingKey;
    segs.put(objectSegment());
    return;
  }

  if (tok == cast(ubyte)'[' ) {
    st = ParsingState.ArrWantingValue;
    segs.put(arraySegment());
    return;
  }
  
  if (tok == cast(ubyte)']' ) {
    popSegment();
    return;
  }

  if (tok == cast(ubyte)'"' ) {
    printFullKey();
    printByte(cast(ubyte)'"');
    st = ParsingState.ArrReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'

  printFullKey();
  printByte(tok);
  st = ParsingState.ArrReadingBareValue;
}

void objReadingStringValue(ubyte tok) {
  if ( tok == cast(ubyte)'\\' ) {
    st = ParsingState.ObjReadingStringValueEscaped;
    printByte(tok);
    return;
  }

  if ( tok == cast(ubyte)'"' ) {
    st = ParsingState.ObjWantingKey;
    printByte(cast(ubyte)'"');
    printNewline(flushOnEveryLine);
    return;
  }

  printByte(tok);
}

void objReadingStringValueEscaped(ubyte tok) {
  printByte(tok);
  st = ParsingState.ObjReadingStringValue;
}

void arrReadingStringValue(ubyte tok) {
  if ( tok == cast(ubyte)'\\' ) {
    st = ParsingState.ArrReadingStringValueEscaped;
    printByte(cast(ubyte)'\\');
    return;
  }

  if ( tok == cast(ubyte)'"' ) {
    st = ParsingState.ArrWantingValue;
    printByte(cast(ubyte)'"');
    printNewline(flushOnEveryLine);
    return;
  }

  printByte(tok);
}

void arrReadingStringValueEscaped(ubyte tok) {
  printByte(tok);
  st = ParsingState.ArrReadingStringValue;
}

void objReadingBareValue(ubyte tok) {
  if (tok == cast(ubyte)'}') {
    printNewline(flushOnEveryLine);
    popSegment();
    return;
  }

  if ( isWhite(tok) || tok == cast(ubyte)',' ) {
    printNewline(flushOnEveryLine);
    st = ParsingState.ObjWantingKey;
    return;
  }

  printByte(tok);
}

void arrReadingBareValue(ubyte tok) {
  if (tok == cast(ubyte)']') {
    printNewline(flushOnEveryLine);
    popSegment();
    return;
  }

  if ( isWhite(tok) || tok == cast(ubyte)',' ) {
    printNewline(flushOnEveryLine);
    st = ParsingState.ArrWantingValue;
    return;
  }

  printByte(tok);
}

