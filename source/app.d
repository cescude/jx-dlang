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
union SegmentData {
  int idx;
  Appender!(ubyte[]) key;
};

struct Segment {
  SegmentType type;
  SegmentData data;
}

void main()
{
  Document doc = {};

	foreach (const ubyte[] buffer; stdin.chunks(4096)) {
    for (size_t i=0; i<buffer.length; i++) {
      doc.feed(buffer[i]);
    }
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
  s.data.key = appender!(ubyte[]);
  return s;
}

Segment arraySegment() {
  Segment s;
  s.type = SegmentType.JsonArray;
  s.data.idx = 0;
  return s;
}

bool isWhite(ubyte b) {
  return b <= cast(ubyte)' ';
}

S last(S)(Appender!(S[]) app) {
  return app[][app[].length-1];
}

void pop(S)(ref Appender!(S[]) app) {
  app.shrinkTo(app[].length-1);
}

void writeFullKey(const Document doc) {
  foreach (i, Segment s; doc.segs[]) {
    if ( i > 0 ) {
      write('.');
    }
    final switch (s.type) {
      case SegmentType.JsonObject:
        write(cast(string)s.data.key[]);
        break;
      case SegmentType.JsonArray:
        write(s.data.idx-1);
        break;
    }
  }
  write(" ");
}

void root(ref Document doc, ubyte tok) {
  //write("root", cast(char)tok);
  switch (tok) {
    case cast(ubyte)'{':
      doc.st = ParsingState.ObjWantingKey;
      doc.segs.put(objectSegment());
      break;
    case cast(ubyte)'[':
      doc.st = ParsingState.ArrWantingValue;
      doc.segs.put(arraySegment());
      break;
    default:
      write(cast(char)tok);
      break;
  }
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


void objWantingKey(ref Document doc, ubyte tok) {
  //write("objWantingKey", cast(char)tok);
  // {     "some"   : "thing" }
  //  1     2
  // {"some":"thing"  , "else": true }
  //                1    2
  // {"some":"thing"   }
  //                1  2
  if (isWhite(tok) || tok == cast(ubyte)',') return;
  if (tok == cast(ubyte)'"') {
    doc.st = ParsingState.ObjReadingKey;
    doc.segs.last.data.key.clear();
    return;
  }
  if (tok == cast(ubyte)'}') {
    popSegment(doc);
    return;
  }

  // bad JSON?
  write("DEBUG BAD THINGS #1");
  doc.st = ParsingState.Root;
  doc.segs.clear();
  doc.escape = false;
}

void objReadingKey(ref Document doc, ubyte tok) {
  //write("objReadingKey", cast(char)tok);
  if (doc.escape) {
    doc.segs.last.data.key.put(tok);
    doc.escape = false;
    return;
  }

  switch (tok) {
    case cast(ubyte)'\\':
      doc.escape = true;
      doc.segs.last.data.key.put(tok);
      return;
    case cast(ubyte)'"':
      doc.st = ParsingState.ObjWantingValue;
      return;
    default:
      doc.segs.last.data.key.put(tok);
      return;
  }
}

void objWantingValue(ref Document doc, ubyte tok) {
  //write("TODO, but with key=", cast(string)doc.segs.last.data.key[]);
  if (isWhite(tok) || tok == cast(ubyte)':') return;

  switch (tok) {
    case cast(ubyte)'{':
      doc.st = ParsingState.ObjWantingKey;
      doc.segs.put(objectSegment());
      return;
    case cast(ubyte)'[':
      doc.st = ParsingState.ArrWantingValue;
      doc.segs.put(arraySegment());
      return;

    case cast(ubyte)'"':
      writeFullKey(doc);
      write('"');
      doc.st = ParsingState.ObjReadingStringValue;
      return;

    // TODO: If we wanted to make sure the value is valid, could do
    // case 't', 'f', '0-9', 'n'
    default:
      writeFullKey(doc);
      write(cast(char)tok);
      doc.st = ParsingState.ObjReadingBareValue;
      return;
  }
}

void arrWantingValue(ref Document doc, ubyte tok) {
  if (isWhite(tok) || tok == cast(ubyte)',') return;

  //doc.segs.last.data.idx = 5;
  doc.segs[][doc.segs[].length-1].data.idx++;
  
  switch (tok) {
    case cast(ubyte)'{':
      doc.st = ParsingState.ObjWantingKey;
      doc.segs.put(objectSegment());
      break;
    case cast(ubyte)'[':
      doc.st = ParsingState.ArrWantingValue;
      doc.segs.put(arraySegment());
      break;
    case cast(ubyte)']':
      popSegment(doc);
      return;

    case cast(ubyte)'"':
      writeFullKey(doc);
      write('"');
      doc.st = ParsingState.ArrReadingStringValue;
      break;

    // TODO: If we wanted to make sure the value is valid, could do
    // case 't', 'f', '0-9', 'n'
    default:
      writeFullKey(doc);
      write(cast(char)tok);
      doc.st = ParsingState.ArrReadingBareValue;
      break;
  }
}

void readingStringValue(ref Document doc, ubyte tok, ParsingState nextState) {
  if (doc.escape) {
    write(cast(char)tok);
    doc.escape = false;
    return;
  }

  if ( tok == cast(ubyte)'\\' ) {
    doc.escape = true;
    write('\\');
    return;
  }

  if ( tok == cast(ubyte)'"' ) {
    doc.st = nextState;
    writeln('"');
    return;
  }

  write(cast(char)tok);
}

void readingBareValue(ref Document doc, ubyte tok, ParsingState nextState) {
  if (tok == cast(ubyte)']') {
    // todo: if nextState != ParsingState.ArrWantingValue we have bad JSON
    writeln();
    popSegment(doc);
    return;
  }

  if (tok == cast(ubyte)'}') {
    // todo: if nextState != ObjWantingKey we have bad json
    writeln();
    popSegment(doc);
    return;
  }

  if ( isWhite(tok) || tok == cast(ubyte)',' ) {
    writeln();
    doc.st = nextState;
    return;
  }

  write(cast(char)tok);
}

