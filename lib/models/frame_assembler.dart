import 'dart:typed_data';

import 'udp_hdr.dart';

class FrameAssembler {
  final _map = <int, _Pending>{};
  int _lastGoodSeq = -1;

  Uint8List? push(UdpHdr h, Uint8List payload) {
    // descarta frames demasiado viejos para evitar “goma”
    if (_lastGoodSeq != -1 && h.seq + 32 < _lastGoodSeq) return null;

    final p = _map.putIfAbsent(h.seq, () => _Pending(h.frameLen, h.fragCnt));
    p.add(h.fragIdx, payload);

    // limpieza para limitar memoria
    if (_map.length > 48) {
      final keys = _map.keys.toList()..sort();
      for (int i = 0; i < keys.length - 24; ++i) {
        _map.remove(keys[i]);
      }
    }

    if (p.isComplete) {
      _lastGoodSeq = h.seq;
      _map.remove(h.seq);
      return p.join();
    }
    return null;
  }
}

class _Pending {
  final int total;
  final int fragCnt;
  final List<Uint8List?> frags;
  int arrived = 0;

  _Pending(this.total, this.fragCnt)
      : frags = List<Uint8List?>.filled(fragCnt, null, growable: false);

  void add(int idx, Uint8List data) {
    if (idx < 0 || idx >= fragCnt) return;
    if (frags[idx] == null) {
      frags[idx] = data;
      arrived++;
    }
  }

  bool get isComplete => arrived == fragCnt;

  Uint8List join() {
    final out = Uint8List(total);
    int off = 0;
    for (final f in frags) {
      final d = f!;
      out.setRange(off, off + d.length, d);
      off += d.length;
    }
    return out;
  }
}
