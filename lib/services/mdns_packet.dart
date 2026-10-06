import 'dart:io';
import 'dart:typed_data';

sealed class MdnsRecordData {
  const MdnsRecordData();
}

class MdnsNameData extends MdnsRecordData {
  final String name;

  const MdnsNameData(this.name);
}

class MdnsSrvData extends MdnsRecordData {
  final String target;
  final int port;

  const MdnsSrvData({required this.target, required this.port});
}

class MdnsTxtData extends MdnsRecordData {
  final Map<String, String> values;

  const MdnsTxtData(this.values);
}

class MdnsAddressData extends MdnsRecordData {
  final String address;

  const MdnsAddressData(this.address);
}

class MdnsUnknownData extends MdnsRecordData {
  const MdnsUnknownData();
}

class MdnsRecord {
  final String name;
  final int type;
  final Duration ttl;
  final MdnsRecordData data;

  const MdnsRecord({
    required this.name,
    required this.type,
    required this.ttl,
    required this.data,
  });
}

class MdnsPacketParser {
  const MdnsPacketParser();

  List<MdnsRecord> parse(List<int> packet) {
    if (packet.length < 12) {
      throw const FormatException('mDNS packet is shorter than its header.');
    }

    final bytes = Uint8List.fromList(packet);
    final cursor = _Cursor(bytes, 0);
    cursor.readUint16();
    cursor.readUint16();
    final questionCount = cursor.readUint16();
    final answerCount = cursor.readUint16();
    final authorityCount = cursor.readUint16();
    final additionalCount = cursor.readUint16();

    for (var i = 0; i < questionCount; i++) {
      _readName(cursor);
      cursor.skip(4);
    }

    final records = <MdnsRecord>[];
    final recordCount = answerCount + authorityCount + additionalCount;
    for (var i = 0; i < recordCount; i++) {
      records.add(_readRecord(cursor));
    }
    return records;
  }

  MdnsRecord _readRecord(_Cursor cursor) {
    final name = _readName(cursor);
    final type = cursor.readUint16();
    cursor.readUint16();
    final ttlSeconds = cursor.readUint32();
    final dataLength = cursor.readUint16();
    final dataStart = cursor.offset;
    final dataEnd = dataStart + dataLength;
    if (dataEnd > cursor.bytes.length) {
      throw const FormatException('mDNS record exceeds packet length.');
    }

    MdnsRecordData data;
    switch (type) {
      case 1:
        if (dataLength != 4) {
          data = const MdnsUnknownData();
        } else {
          data = MdnsAddressData(
            InternetAddress.fromRawAddress(
              cursor.bytes.sublist(dataStart, dataEnd),
            ).address,
          );
        }
        break;
      case 12:
        data = MdnsNameData(_readName(_Cursor(cursor.bytes, dataStart)));
        break;
      case 16:
        data = MdnsTxtData(_readTxt(cursor.bytes, dataStart, dataEnd));
        break;
      case 28:
        if (dataLength != 16) {
          data = const MdnsUnknownData();
        } else {
          data = MdnsAddressData(
            InternetAddress.fromRawAddress(
              cursor.bytes.sublist(dataStart, dataEnd),
            ).address,
          );
        }
        break;
      case 33:
        final dataCursor = _Cursor(cursor.bytes, dataStart);
        dataCursor.skip(4);
        final port = dataCursor.readUint16();
        data = MdnsSrvData(target: _readName(dataCursor), port: port);
        break;
      default:
        data = const MdnsUnknownData();
    }
    cursor.offset = dataEnd;

    return MdnsRecord(
      name: name,
      type: type,
      ttl: Duration(seconds: ttlSeconds),
      data: data,
    );
  }

  Map<String, String> _readTxt(Uint8List bytes, int start, int end) {
    final values = <String, String>{};
    var offset = start;
    while (offset < end) {
      final length = bytes[offset++];
      if (offset + length > end) {
        throw const FormatException('Invalid mDNS TXT record.');
      }
      final text = String.fromCharCodes(bytes.sublist(offset, offset + length));
      offset += length;
      final separator = text.indexOf('=');
      if (separator < 0) {
        values[text] = '';
      } else {
        values[text.substring(0, separator)] = text.substring(separator + 1);
      }
    }
    return values;
  }

  String _readName(_Cursor cursor) {
    final labels = <String>[];
    final visited = <int>{};
    var position = cursor.offset;
    var jumped = false;

    while (true) {
      if (position >= cursor.bytes.length || !visited.add(position)) {
        throw const FormatException('Invalid mDNS compressed name.');
      }
      final length = cursor.bytes[position];
      if (length == 0) {
        if (!jumped) cursor.offset = position + 1;
        break;
      }
      if ((length & 0xc0) == 0xc0) {
        if (position + 1 >= cursor.bytes.length) {
          throw const FormatException('Incomplete mDNS compression pointer.');
        }
        final pointer = ((length & 0x3f) << 8) | cursor.bytes[position + 1];
        if (!jumped) cursor.offset = position + 2;
        position = pointer;
        jumped = true;
        continue;
      }
      if ((length & 0xc0) != 0 || position + 1 + length > cursor.bytes.length) {
        throw const FormatException('Invalid mDNS label.');
      }
      labels.add(
        String.fromCharCodes(
          cursor.bytes.sublist(position + 1, position + 1 + length),
        ),
      );
      position += length + 1;
      if (!jumped) cursor.offset = position;
    }
    return labels.join('.');
  }
}

class MdnsQueryEncoder {
  const MdnsQueryEncoder();

  List<int> query(Iterable<(String, int)> questions) {
    final selected = questions.toList();
    final builder = BytesBuilder();
    builder.add(_uint16(0));
    builder.add(_uint16(0));
    builder.add(_uint16(selected.length));
    builder.add(List<int>.filled(6, 0));

    for (final question in selected) {
      builder.add(_encodeName(question.$1));
      builder.add(_uint16(question.$2));
      builder.add(_uint16(1));
    }
    return builder.takeBytes();
  }

  List<int> _encodeName(String name) {
    final builder = BytesBuilder();
    for (final label in name.replaceFirst(RegExp(r'\.$'), '').split('.')) {
      final bytes = label.codeUnits;
      if (bytes.length > 63) {
        throw ArgumentError.value(name, 'name', 'DNS label is too long.');
      }
      builder.addByte(bytes.length);
      builder.add(bytes);
    }
    builder.addByte(0);
    return builder.takeBytes();
  }

  List<int> _uint16(int value) => [value >> 8, value & 0xff];
}

class _Cursor {
  final Uint8List bytes;
  int offset;

  _Cursor(this.bytes, this.offset);

  int readUint16() {
    _require(2);
    final value = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    return value;
  }

  int readUint32() {
    _require(4);
    final value =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    return value;
  }

  void skip(int count) {
    _require(count);
    offset += count;
  }

  void _require(int count) {
    if (offset + count > bytes.length) {
      throw const FormatException('Unexpected end of mDNS packet.');
    }
  }
}
