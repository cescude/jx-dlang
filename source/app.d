import std.stdio;
import std.array;

struct Document {
  ParsingState st = ParsingState.Root;
  bool escape = false;
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
  Document doc = {};

	foreach (const ubyte[] buffer; stdin.chunks(1)) {
    for (size_t i=0; i<buffer.length; i++) {
      doc.feed(buffer[i]);
    }
  }
}

void put(S)(S s) {
  stdout.write(s);
}

void newline() {
  stdout.write("\n");
  stdout.flush();
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
  foreach (i, Segment s; doc.segs[]) {
    if ( i > 0 ) {
      put('.');
    }
    final switch (s.type) {
      case SegmentType.JsonObject:
        put(cast(string)s.key[]);
        break;
      case SegmentType.JsonArray:
        put(s.idx-1);
        break;
    }
  }
  put("  ");
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

  put(cast(char)tok);
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
    put('"');
    doc.st = ParsingState.ObjReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'. Don't really care though!

  writeFullKey(doc);
  put(cast(char)tok);
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
    put('"');
    doc.st = ParsingState.ArrReadingStringValue;
    return;
  }

  // TODO: If we wanted to make sure the value is valid, could do
  // case 't', 'f', '0-9', 'n'

  writeFullKey(doc);
  put(cast(char)tok);
  doc.st = ParsingState.ArrReadingBareValue;
}

void readingStringValue(ref Document doc, ubyte tok, ParsingState nextState) {
  if (doc.escape) {
    put(cast(char)tok);
    doc.escape = false;
    return;
  }

  if ( tok == cast(ubyte)'\\' ) {
    doc.escape = true;
    put('\\');
    return;
  }

  if ( tok == cast(ubyte)'"' ) {
    doc.st = nextState;
    put('"');
    newline();
    return;
  }

  stdout.write(cast(char)tok);
}

void readingBareValue(ref Document doc, ubyte tok, ParsingState nextState) {
  if (tok == cast(ubyte)']') {
    // todo: if nextState != ParsingState.ArrWantingValue we have bad JSON
    newline();
    popSegment(doc);
    return;
  }

  if (tok == cast(ubyte)'}') {
    // todo: if nextState != ObjWantingKey we have bad json
    newline();
    popSegment(doc);
    return;
  }

  if ( isWhite(tok) || tok == cast(ubyte)',' ) {
    newline();
    doc.st = nextState;
    return;
  }

  put(cast(char)tok);
}

