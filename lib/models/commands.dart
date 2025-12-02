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

// Opcional: giros explícitos
const List<String> synTurnL = ['gira a la izquierda', 'giro izquierda'];
const List<String> synTurnR = ['gira a la derecha', 'giro derecha'];

// Si luego quieres SIT/STAND, se pueden mapear a otros chars
// por ahora los ignoro para no ensuciar el protocolo.
const List<String> synSit  = ['sentado', 'siéntate', 'sientate'];
const List<String> synStnd = ['parado', 'de pie', 'levántate', 'levantate', 'arriba'];

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

  // ⚠️ Aquí mapeamos directamente al protocolo de la Pi:
  add(synFwd,   'I'); // forward
  add(synStop,  'K'); // stop
  add(synL,     'J'); // left strafe
  add(synR,     'L'); // right strafe
  add(synTurnL, 'U'); // left turn
  add(synTurnR, 'O'); // right turn

  // (Opcional: por ahora SIT/STAND los podrías mapear a 'K' = stop)
  // add(synSit,  'K');
  // add(synStnd, 'K');

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
