import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';
import 'package:web/web.dart' hide Text;

void main() {
  runApp(MaterialApp(home: const MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  static const int gridWidth = 14;
  static const int gridHeight = 8;

  WritableStreamDefaultWriter? writer;
  List<bool> electrodes = List.filled(gridWidth * gridHeight, false);
  Resevoir rtl = Resevoir.start();
  Resevoir rbl = Resevoir.start();
  Resevoir rtr = Resevoir.start();
  Resevoir rbr = Resevoir.start();
  List<(int, int)> waters = [];
  Ticker? ticker;
  SerialPort? serialPort;
  static const int msDelay = 400;

  @override
  void initState() {
    super.initState();
  }

  void requestPort() {
    window.navigator.serial.requestPort().toDart.then((SerialPort port) {
      serialPort = port;
      port.open(baudRate: 115200).toDart.then((_) {
        setState(() {
          writer = port.writable!.getWriter();
          ticker = createTicker(tick)..start();
        });
      });
    });
  }

  int encodeResevoirs(Resevoir bottom, Resevoir top) {
    int result = 0;
    if (top.end) {
      result |= 0x1;
    }
    if (top.sides) {
      result |= 0x2;
    }
    if (top.center) {
      result |= 0x4;
    }
    if (top.main) {
      result |= 0x8;
    }
    if (bottom.main) {
      result |= 0x10;
    }
    if (bottom.center) {
      result |= 0x20;
    }
    if (bottom.sides) {
      result |= 0x40;
    }
    if (bottom.end) {
      result |= 0x80;
    }
    return result;
  }

  void tick(_) {
    calculateWater();
    Uint8List packet = Uint8List(32);
    packet[0] = encodeResevoirs(rbl, rtl);
    for (int x = 0; x < gridWidth; x++) {
      int columnByte = 0;
      for (int y = 0; y < gridHeight; y++) {
        if (electrodes[y * gridWidth + x]) {
          columnByte |= (1 << y);
        }
      }
      packet[x + 1] = columnByte;
    }
    packet[15] = encodeResevoirs(rbr, rtr);
    writer!.write(packet.toJS);
  }

  Future<void> _dispense(
    void Function(Resevoir resevoir) setResevoirState,
    int electrodeAtEndX,
    int electrodeAtEndY,
  ) async {
    if (waters.any((e) => e.$1 == electrodeAtEndX && e.$2 == electrodeAtEndY)) {
      return;
    }
    setResevoirState(Resevoir(true, true, false, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, true, false, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    electrodes[electrodeAtEndY * gridWidth + electrodeAtEndX] = true;
    waters.add((electrodeAtEndX, electrodeAtEndY));
    setResevoirState(Resevoir(false, true, true, true));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(false, false, false, true));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, true, false, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, false, true, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, false, false, false));
  }

  void dispenseTL() {
    _dispense(
      (r) => setState(() {
        rtl = r;
      }),
      0,
      1,
    );
  }

  void dispenseBL() {
    _dispense(
      (r) => setState(() {
        rbl = r;
      }),
      0,
      6,
    );
  }

  void dispenseTR() {
    _dispense(
      (r) => setState(() {
        rtr = r;
      }),
      13,
      1,
    );
  }

  void dispenseBR() {
    _dispense(
      (r) => setState(() {
        rbr = r;
      }),
      13,
      6,
    );
  }

  Future<void> _intake(
    void Function(Resevoir resevoir) setResevoirState,
    int electrodeAtEndX,
    int electrodeAtEndY,
  ) async {
    if (!waters.any(
      (e) => e.$1 == electrodeAtEndX && e.$2 == electrodeAtEndY,
    )) {
      return;
    }

    setResevoirState(Resevoir(true, false, false, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, false, true, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, true, false, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(false, false, false, true));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(false, true, true, true));
    electrodes[electrodeAtEndY * gridWidth + electrodeAtEndX] = false;
    waters.remove((electrodeAtEndX, electrodeAtEndY));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, true, false, false));
    await Future.delayed(Duration(milliseconds: msDelay));
    setResevoirState(Resevoir(true, true, false, false));
  }

  void intakeTL() {
    _intake(
      (r) => setState(() {
        rtl = r;
      }),
      0,
      1,
    );
  }

  void intakeBL() {
    _intake(
      (r) => setState(() {
        rbl = r;
      }),
      0,
      6,
    );
  }

  void intakeTR() {
    _intake(
      (r) => setState(() {
        rtr = r;
      }),
      13,
      1,
    );
  }

  void intakeBR() {
    _intake(
      (r) => setState(() {
        rbr = r;
      }),
      13,
      6,
    );
  }

  @override
  void dispose() {
    ticker?.dispose();
    serialPort?.close();
    super.dispose();
  }

  List<(int, int)> snake = [(0, 6)];

  KeyEventResult onKeyEvent(FocusNode focusNode, KeyEvent keyEvent) {
    if (keyEvent.logicalKey == LogicalKeyboardKey.space) {
      if (keyEvent is KeyDownEvent) {
        dispenseBL();
      }
      return KeyEventResult.handled;
    }
    if (keyEvent.logicalKey == LogicalKeyboardKey.shiftLeft) {
      if (keyEvent is KeyDownEvent) {
        intakeBL();
      }
      return KeyEventResult.handled;
    }
    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (keyEvent is KeyDownEvent) {
        if (snake.first.$1 + 1 < gridWidth && !snake.contains((snake.first.$1 + 1, snake.first.$2))) {
          electrodes[snake.last.$1 + snake.last.$2 * gridWidth] = false;
          electrodes[snake.first.$1 + snake.first.$2 * gridWidth + 1] = true;
          setState(() {
            snake.insert(0, (snake.first.$1 + 1, snake.first.$2));
            if (!waters.contains(snake.first)) {
              snake.removeLast();
            }
          });
        }
      }

      return KeyEventResult.handled;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (keyEvent is KeyDownEvent) {
        if (snake.first.$1 > 0 && !snake.contains((snake.first.$1 - 1, snake.first.$2))) {
          electrodes[snake.last.$1 + snake.last.$2 * gridWidth] = false;
          electrodes[snake.first.$1 + snake.first.$2 * gridWidth - 1] = true;
          setState(() {
            snake.insert(0, (snake.first.$1 - 1, snake.first.$2));
            if (!waters.contains(snake.first)) {
              snake.removeLast();
            }
          });
        }
      }
      return KeyEventResult.handled;
    }
    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (keyEvent is KeyDownEvent) {
        if (snake.first.$2 + 1 < gridHeight && !snake.contains((snake.first.$1, snake.first.$2 + 1))) {
          electrodes[snake.last.$1 + snake.last.$2 * gridWidth] = false;
          electrodes[snake.first.$1 + (snake.first.$2 + 1) * gridWidth] = true;
          setState(() {
            snake.insert(0, (snake.first.$1, snake.first.$2 + 1));
            if (!waters.contains(snake.first)) {
              snake.removeLast();
            }
          });
        }
      }
      return KeyEventResult.handled;
    }

    if (keyEvent.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (keyEvent is KeyDownEvent) {
        if (snake.first.$2 > 0 &&  !snake.contains((snake.first.$1, snake.first.$2 - 1))) {
          electrodes[snake.last.$1 + snake.last.$2 * gridWidth] = false;
          electrodes[snake.first.$1 + (snake.first.$2 - 1) * gridWidth] = true;
          setState(() {
            snake.insert(0, (snake.first.$1, snake.first.$2 - 1));
            if (!waters.contains(snake.first)) {
              snake.removeLast();
            }
          });
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void calculateWater() {
    for ((int, int) water in waters) {
      if (!electrodes[water.$1 + water.$2 * gridWidth]) {
        calculateDrop(water);
      }
    }
  }

  void calculateDrop((int, int) drop) {
    setState(() {
      int x = drop.$1;
      int y = drop.$2;
      List<(int, int)> checked = [];
      List<(int, int)> frontier = [(x, y)];
      void add((int, int) adder) {
        if (!frontier.contains(adder) && !checked.contains(adder)) {
          frontier.add(adder);
        }
      }

      while (frontier.isNotEmpty) {
        x = frontier.last.$1;
        y = frontier.last.$2;
        assert(x < gridWidth);
        assert(y < gridHeight);
        assert(x + y * gridWidth < electrodes.length);
        checked.add(frontier.last);
        frontier.removeLast();
        if (electrodes[x + y * gridWidth] || drop == (x, y)) {
          if (!waters.contains((x, y))) {
            waters.remove(drop);
            waters.add((x, y));
            return;
          }
          if (x > 0) {
            add((x - 1, y));
          }
          if (x + 1 < gridWidth) {
            add((x + 1, y));
          }
          if (y > 0) {
            add((x, y - 1));
          }
          if (y + 1 < gridHeight) {
            add((x, y + 1));
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: onKeyEvent,
      child: Scaffold(
        body: serialPort == null
            ? OutlinedButton(
                onPressed: requestPort,
                child: Text('Select serial port'),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  double waterSize = min(
                    constraints.maxHeight / gridHeight,
                    constraints.maxWidth / gridWidth,
                  );
                  return Stack(
                    children: [
                      ...waters.map(
                        (e) => Positioned(
                          left: waterSize * e.$1,
                          top: waterSize * e.$2,
                          child: Container(
                            width: waterSize,
                            height: waterSize,
                            color: snake.contains(e) ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

extension type Resevoir._(
  ({bool main, bool center, bool sides, bool end}) value
) {
  factory Resevoir.start() =>
      Resevoir._((main: true, center: false, sides: false, end: false));
  factory Resevoir(bool main, bool center, bool sides, bool end) =>
      Resevoir._((main: main, center: center, sides: sides, end: end));
  bool get main => value.main;
  bool get center => value.center;
  bool get sides => value.sides;
  bool get end => value.end;
}
