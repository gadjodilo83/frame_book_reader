import 'dart:async';
import 'dart:io'; // Für File-Operationen
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/tx/plain_text.dart';
import 'package:simple_frame_app/tx/code.dart'; // Für TxCode hinzugefügt
import 'tap_data_response.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}



class MainAppState extends State<MainApp> with SimpleFrameAppState {
  StreamSubscription<int>? _tapSubs;
  String? _message;
  final List<String> _wrappedChunks = []; // Liste für umgebrochene Zeilen
  List<String> _visibleLines = [];
  int _currentLine = 0;
  bool _isTyping = false;
  double _typewriterSpeed = 0.03; // Sekunden pro Buchstabe
  int _currentCharIndex = 0;
  int _maxLinesOnScreen = 3; // Anzahl der angezeigten Zeilen auf dem Bildschirm (anpassbar)
  final int _chunkSize = 32; // Maximale Zeichenanzahl pro Zeile
  ScrollController _scrollController = ScrollController();
  final GlobalKey _footerKey = GlobalKey();
  double lineHeight = 50.0; // Höhe jeder Zeile (anpassbar)


  double get footerButtonsHeight {
    final RenderBox? renderBox = _footerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      return renderBox.size.height;
    } else {
      // Standardhöhe verwenden, wenn die Messung noch nicht verfügbar ist
      return 50.0;
    }
  }

  int _startLine = 0; // Startzeile für den Typewriter-Effekt

  Timer? _keepAliveTimer;
  Timer? _tapEnableTimer;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

@override
void initState() {
  super.initState();
  _scrollController = ScrollController();
}

@override
void dispose() {
  _scrollController.dispose();
  super.dispose();
}



  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null) {
        File file = File(result.files.single.path!); // Verwendung von dart:io

        String content = await file.readAsString();
        _log.info('Dateiinhalt erfolgreich geladen.');

        _wrappedChunks.clear();
        setState(() {
          // Ersetze Zeilenumbrüche durch Leerzeichen, um den Text als einen Absatz zu behandeln
          String singleParagraph = content.replaceAll('\n', ' ');
          _wrappedChunks.addAll(_wrapTextToFit(singleParagraph, _chunkSize));
          _currentLine = 0;
          _currentCharIndex = 0;
          _visibleLines.clear();
        });

        // Frame abonnieren für Tap-Ereignisse
        if (frame != null) {
          _tapSubs?.cancel();
          _tapSubs = tapDataResponse(
            frame!.dataResponse,
            const Duration(milliseconds: 300),
          ).listen(
            (taps) {
              _message = '$taps-tap detected';
              _log.info(_message!);
              setState(() {
                if (_isTyping) {
                  _stopTypewriterEffect();
                } else {
                  _startTypewriterEffect();
                }
              });
            },
            onError: (error) {
              _log.warning('Tap subscription error: $error');
            },
            onDone: () {
              _log.warning('Tap subscription closed.');
            },
          );

          // Aktiviert Tap-Event-Abonnement auf dem Frame
          await frame!.sendMessage(TxCode(msgCode: 0x10, value: 1));

          // Starten Sie die Keep-Alive- und Tap-Enable-Timer
          _startKeepAlive();
          _startTapEnableTimer();

          // Prompt the user to begin tapping
          await frame!
              .sendMessage(TxPlainText(msgCode: 0x12, text: 'Tap away!'));
        }
      } else {
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
      }
    } catch (e) {
      _log.fine('Fehler bei der Ausführung der Anwendungslogik: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    _wrappedChunks.clear();
    _visibleLines.clear();
    _stopTypewriterEffect();
    _tapSubs?.cancel(); // Stoppe das Abonnement für Tap-Ereignisse

    // Stoppen Sie die Keep-Alive- und Tap-Enable-Timer
    _stopKeepAlive();
    _stopTapEnableTimer();

    if (frame != null) {
      await frame!.sendMessage(
          TxCode(msgCode: 0x10, value: 0)); // Tap-Abonnement deaktivieren
    }
    if (mounted) setState(() {});
  }

void _startKeepAlive() {
  // _keepAliveTimer?.cancel(); // Vorhandenen Timer stoppen
  // _keepAliveTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
  //   if (frame != null) {
  //     try {
  //       await frame!.sendMessage(TxCode(msgCode: 0x11, value: 0)); // Keep-Alive-Nachricht
  //       _log.info('Keep-Alive-Nachricht an Frame gesendet.');
  //     } catch (e) {
  //       _log.warning('Fehler beim Senden der Keep-Alive-Nachricht: $e');
  //     }
  //   }
  // });
}


  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

void _startTapEnableTimer() {
  _tapEnableTimer?.cancel(); // Vorhandenen Timer stoppen
  _tapEnableTimer = Timer.periodic(Duration(minutes: 1), (timer) async {
    if (frame != null) {
      try {
        await frame!.sendMessage(TxCode(msgCode: 0x10, value: 1)); // Tap-Ereignisse aktivieren
        _log.info('Tap-Ereignisse auf Frame reaktiviert.');
      } catch (e) {
        _log.warning('Fehler beim Reaktivieren der Tap-Ereignisse: $e');
      }
    }
  });
}


  void _stopTapEnableTimer() {
    _tapEnableTimer?.cancel();
    _tapEnableTimer = null;
  }

void _startTypewriterEffect() {
  if (_isTyping) return; // Verhindere mehrfaches Starten

  // Überprüfen, ob das Ende des Textes erreicht wurde
  if (_currentLine >= _wrappedChunks.length) {
    _currentLine = 0;
    _currentCharIndex = 0;
    _visibleLines.clear();
    _sendTextToFrame(clear: true);
    _log.info('Typewriter-Effekt von vorne gestartet.');
  }

  _isTyping = true;
  _log.info('Typewriter-Effekt gestartet.');

  _runTypewriterEffect();
}


  void _stopTypewriterEffect() {
    _isTyping = false;
    _log.info('Typewriter-Effekt gestoppt.');
  }

  Future<void> _runTypewriterEffect() async {
    while (_isTyping && _currentLine < _wrappedChunks.length) {
      String wrappedLine = _wrappedChunks[_currentLine];
      _log.info('Verarbeite Zeile $_currentLine: "$wrappedLine"');

      for (; _currentCharIndex < wrappedLine.length; _currentCharIndex += 2) {
        if (!_isTyping) break;

        String charsToAdd = wrappedLine.substring(
          _currentCharIndex,
          (_currentCharIndex + 2 <= wrappedLine.length)
            ? _currentCharIndex + 2
            : wrappedLine.length,
        );

        _addCharacterToVisibleText(charsToAdd);

        await _sendTextToFrame();

        await Future.delayed(
          Duration(milliseconds: (_typewriterSpeed * 1000).toInt()),
        );
      }

		if (!_isTyping) break;

		_currentCharIndex = 0;
		_currentLine++;

		if (_visibleLines.length > _maxLinesOnScreen) {
		  _visibleLines.removeAt(0);
		  _log.info('Entferne oberste Zeile, um zu scrollen.');
		}

		setState(() {});

		// Scrollen Sie zum aktuellen Eintrag
		_scrollToCurrentLine();

		await Future.delayed(Duration(milliseconds: 50));
	  }

	  _isTyping = false;
	  _log.info('Typewriter-Effekt abgeschlossen.');

	  // Überprüfen, ob das Ende des Textes erreicht wurde
	  if (_currentLine >= _wrappedChunks.length) {
		_currentLine = 0;
		_currentCharIndex = 0;
		_visibleLines.clear();
		_sendTextToFrame(clear: true);
		_log.info('Typewriter-Effekt hat das Ende des Textes erreicht und wurde zurückgesetzt.');
	  }
	}



  List<String> _wrapTextToFit(String text, int maxCharsPerLine) {
    List<String> lines = [];
    List<String> words =
        text.split(RegExp(r'\s+')); // Splitte anhand von Leerzeichen
    String currentLine = '';

    for (String word in words) {
      word = word.trim();

      if (word.isEmpty) continue;

      int prospectiveLength =
          currentLine.isEmpty ? word.length : currentLine.length + 1 + word.length;

      if (prospectiveLength <= maxCharsPerLine) {
        currentLine += (currentLine.isEmpty ? '' : ' ') + word;
      } else {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
        }

        if (word.length > maxCharsPerLine) {
          int start = 0;
          while (start < word.length) {
            int end = (start + maxCharsPerLine) < word.length
                ? start + maxCharsPerLine
                : word.length;
            lines.add(word.substring(start, end));
            start += maxCharsPerLine;
          }
          currentLine = '';
        } else {
          currentLine = word;
        }
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }

  Future<void> _sendTextToFrame({bool clear = false}) async {
    try {
      if (frame == null) {
        _log.warning('Frame ist nicht verbunden.');
        return;
      }

      String fullText = clear ? "" : _visibleLines.join('\n');

      await frame!.sendMessage(TxPlainText(
        msgCode: 0x12,
        text: fullText,
      ));
      _log.info(
          'Nachricht an Frame gesendet: "${clear ? "Leeren Text gesendet" : fullText}"');
    } catch (e) {
      _log.warning('Fehler beim Senden der Nachricht an das Frame: $e');
    }
  }

void _addCharacterToVisibleText(String char) {
  if (_currentCharIndex == 0) {
    _visibleLines.add(char);
  } else {
    if (_visibleLines.isNotEmpty) {
      _visibleLines[_visibleLines.length - 1] += char;
    } else {
      // Falls _visibleLines leer ist, fügen wir das Zeichen als neue Zeile hinzu
      _visibleLines.add(char);
      _log.warning('Warnung: _visibleLines war leer, neue Zeile hinzugefügt.');
    }
  }
}


void _scrollToCurrentLine() {
  if (_scrollController.hasClients) {
    double totalContentHeight = _wrappedChunks.length * lineHeight;
    double viewportHeight = MediaQuery.of(context).size.height
        - kToolbarHeight
        - MediaQuery.of(context).padding.top
        - MediaQuery.of(context).padding.bottom
        - footerButtonsHeight;

    double maxScrollOffset = totalContentHeight - viewportHeight;
    if (maxScrollOffset < 0) maxScrollOffset = 0;

    double targetOffset = _currentLine * lineHeight;

    // Stellen Sie sicher, dass der Offset innerhalb der Scrollgrenzen liegt
    if (targetOffset > maxScrollOffset) {
      targetOffset = maxScrollOffset;
    }

    if (targetOffset < 0) targetOffset = 0;

    _scrollController.animateTo(
      targetOffset,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}












@override
Widget build(BuildContext context) {
  return MaterialApp(
    title: 'Frame Book Reader',
    theme: ThemeData.dark(),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Frame Book Reader'),
        actions: [getBatteryWidget()],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Tap-Handling für Play/Pause-Funktion auf dem Android-Gerät
          setState(() {
            if (_isTyping) {
              _stopTypewriterEffect();
            } else {
              _startTypewriterEffect();
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController, // ScrollController hinzufügen
                  itemCount: _wrappedChunks.length,
                  itemBuilder: (context, index) {
                    bool isCurrentLine = index == _currentLine;

                    return SizedBox(
                      height: lineHeight, // Verwenden Sie die Klassenvariable
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _startLine = index;
                            _currentLine = _startLine;
                            _currentCharIndex = 0;
                            _visibleLines.clear();
                            _sendTextToFrame(clear: true);
                            _log.info('Startzeile geändert auf: $_startLine');
                          });
                        },
                        child: Container(
                          color: isCurrentLine ? Colors.grey[800] : null,
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.symmetric(horizontal: 8.0), // Optionales Padding
                          child: Text(
                            _wrappedChunks[index],
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.0,
                              fontFamily: 'Courier',
                              fontWeight: isCurrentLine
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrentLine
                                  ? Colors.blue
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Current Line: $_currentLine',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: getFloatingActionButtonWidget(
        const Icon(Icons.file_open),
        const Icon(Icons.close),
      ),
      persistentFooterButtons: [
        Container(
          key: _footerKey, // Fügen Sie das GlobalKey hier hinzu
          child: Row(
            children: [
              ...getFooterButtonsWidget(),
              IconButton(
                icon: Icon(_isTyping ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (_isTyping) {
                    _stopTypewriterEffect();
                  } else {
                    _startTypewriterEffect();
                  }
                  if (mounted) setState(() {});
                },
              ),
              SizedBox(
                width: 200,
                child: Column(
                  children: [
                    Slider(
                      value: _typewriterSpeed,
                      min: 0.03,
                      max: 0.2,
                      divisions: 10,
                      label: 'Typewriter Speed',
                      onChanged: (value) {
                        setState(() {
                          _typewriterSpeed = value;
                          _log.info('Typewriter-Geschwindigkeit geändert auf: $value s/Buchstabe');
                        });
                      },
                    ),
                    Slider(
                      value: _maxLinesOnScreen.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: 'MaxLinesOnScreen',
                      onChanged: (value) {
                        setState(() {
                          _maxLinesOnScreen = value.toInt();
                          _log.info('Anzahl der anzuzeigenden Zeilen geändert auf: $_maxLinesOnScreen');
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
}
