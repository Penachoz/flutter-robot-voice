import 'dart:typed_data';

class UdpHdr {
  // "MJPG" (0x4D4A5047) | seq | ts(64) | frameLen | fragIdx | fragCnt
  final int magic, seq;
  final int tsMsHi, tsMsLo;
  final int frameLen;
  final int fragIdx, fragCnt;

  static const size = 24; // 4 + 4 + 8 + 4 + 2 + 2

  UdpHdr(
    this.magic,
    this.seq,
    this.tsMsHi,
    this.tsMsLo,
    this.frameLen,
    this.fragIdx,
    this.fragCnt,
  );

  static UdpHdr? tryParse(Uint8List d) {
    if (d.lengthInBytes < size) return null;
    final b = ByteData.sublistView(d);
    final magic = b.getUint32(0, Endian.big);
    if (magic != 0x4D4A5047) return null; // "MJPG"

    final seq     = b.getUint32(4, Endian.big);
    final tsHi    = b.getUint32(8, Endian.big);
    final tsLo    = b.getUint32(12, Endian.big);
    final flen    = b.getUint32(16, Endian.big);
    final fragIdx = b.getUint16(20, Endian.big);
    final fragCnt = b.getUint16(22, Endian.big);
    return UdpHdr(magic, seq, tsHi, tsLo, flen, fragIdx, fragCnt);
  }
}
