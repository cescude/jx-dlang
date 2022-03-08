module json;

import std.array;
import std.exception;
import std.stdio : stdin, File, chunks, writeln;

ParsingState st;
bool flushOnEveryLine;
bool printLineNumbers;
ubyte[] filename;
size_t lineNumber;
Appender!(Segment[]) segs;

enum SegmentType {JsonObject, JsonArray};

struct Segment {
  SegmentType type;
  union {
    size_t idx;
    Appender!(ubyte[]) key;
  }
}

void init(bool optFlushOnEveryLine, bool optPrintLineNumbers, ubyte[] optFilename) {
  st = ParsingState.Root;
  flushOnEveryLine = optFlushOnEveryLine;
  printLineNumbers = optPrintLineNumbers;
  filename = optFilename;
  lineNumber = 1;
  segs = appender!(Segment[]);
}

ubyte[4096] writeBuffer;
size_t writeBufferLength = 0;
void flush() nothrow @nogc {
  import core.stdc.stdio : fwrite, stdout;
  fwrite(&writeBuffer[0], ubyte.sizeof, writeBufferLength, stdout);
  // TODO: Is it important to check the return value of fwrite()?
  writeBufferLength = 0;
}

void printByte(ubyte b) nothrow @nogc {
  if (writeBufferLength == writeBuffer.length) {
    flush();
  }
  writeBuffer[writeBufferLength++] = b;
}

void printByteSlice(const ubyte[] buffer) nothrow @nogc {
  foreach (ubyte b; buffer) {
    printByte(b);
  }
}

void printNumber(size_t n) nothrow @nogc {
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

void printNewline(bool doFlush) nothrow @nogc {
  printByte(cast(ubyte)'\n');
  if (doFlush) {
    flush();
  }
}

void printFullKey() nothrow @nogc {
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

enum ParsingState {
  Root,
  ObjWantingKey, 
  ObjReadingKey, ObjReadingKeyEscaped,
  ObjWantingValue, 
  ObjReadingStringValue, ObjReadingStringValueEscaped, ObjReadingBareValue,
  ArrWantingValue, 
  ArrReadingStringValue, ArrReadingStringValueEscaped, ArrReadingBareValue,
}

immutable void function(ubyte)[] processState = [
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

void processStdin(bool withFilename, bool withLineNumbers) {
  init(true, withLineNumbers, withFilename ? cast(ubyte[])"-" : null);

  foreach (const ubyte[] buffer; stdin.chunks(1)) {
    if (buffer[0] == cast(ubyte)'\n') {
      lineNumber++;
    }
    processState[st](buffer[0]);
  }

  flush();
}

void processFile(string filename, bool withFilename, bool withLineNumbers) {
  try {
    auto f = File(filename, "r");

    init(false, withLineNumbers, withFilename ? cast(ubyte[])filename : null);

    foreach (const ubyte[] buffer; f.chunks(4096)) {
      for (size_t i=0; i<buffer.length; i++) {
        if (buffer[i] == cast(ubyte)'\n') {
          lineNumber++;
        }
        processState[st](buffer[i]);
      }
    }
  }
  catch (ErrnoException e) {
    writeln("Unable to read file: ", filename);
  }

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

bool isWhite(ubyte b) nothrow @nogc {
  return b <= cast(ubyte)' ';
}

ref S last(S)(ref Appender!(S[]) app) nothrow @nogc {
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

void objReadingKey(ubyte tok) nothrow {
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

void objReadingStringValue(ubyte tok) nothrow @nogc {
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

void objReadingStringValueEscaped(ubyte tok) nothrow @nogc {
  printByte(tok);
  st = ParsingState.ObjReadingStringValue;
}

void arrReadingStringValue(ubyte tok) nothrow @nogc {
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

void arrReadingStringValueEscaped(ubyte tok) nothrow @nogc {
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

