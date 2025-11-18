class CommandMatch {
  final String keyword;
  final String command;

  const CommandMatch(this.keyword, this.command);
}

// Sinónimos
const List<String> synFwd  = ['avanza', 'adelante', 'avance', 'vamos'];
const List<String> synStop = [
  'alto',
  'para',
  'detente',
  'parate',
  'frena',
  'stop',
  'quieto',
  'basta',
  'deten',
];
const List<String> synL    = ['izquierda', 'izq'];
const List<String> synR    = ['derecha', 'der'];
const List<String> synSit  = ['sentado', 'siéntate', 'sientate'];
const List<String> synStnd = ['parado', 'de pie', 'levántate', 'levantate', 'arriba'];

// Toma la PRIMERA palabra que aparezca en el texto
CommandMatch? matchFirstKeyword(String text) {
  final candidates = <MapEntry<String, String>>[];

  void add(List<String> keys, String cmd) {
    for (final k in keys) {
      final i = text.indexOf(k);
      if (i >= 0) {
        candidates.add(MapEntry('$i|$k', cmd));
      }
    }
  }

  add(synFwd,  'FORWARD');
  add(synStop, 'STOP');
  add(synL,    'LEFT');
  add(synR,    'RIGHT');
  add(synSit,  'SIT');
  add(synStnd, 'STAND');

  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final ia = int.parse(a.key.split('|').first);
    final ib = int.parse(b.key.split('|').first);
    return ia.compareTo(ib);
  });

  final first = candidates.first;
  final kw  = first.key.split('|')[1];
  final cmd = first.value;

  return CommandMatch(kw, cmd);
}
