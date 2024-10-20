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
  List<String> _words = []; // Liste für die Wörter
  int _currentWordIndex = 0;
  bool _isPlaying = false;
  double _baseSpeed = 0.5; // Grundgeschwindigkeit in Sekunden pro Wort
  Timer? _wordTimer;

  Timer? _keepAliveTimer; // Hinzugefügt
  Timer? _tapEnableTimer; // Hinzugefügt

  ScrollController _scrollController = ScrollController();
  final GlobalKey _footerKey = GlobalKey();

  double get footerButtonsHeight {
    final RenderBox? renderBox =
        _footerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      return renderBox.size.height;
    } else {
      // Standardhöhe verwenden, wenn die Messung noch nicht verfügbar ist
      return 50.0;
    }
  }

  int _startWordIndex = 0; // Startwort für RSVP

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
    _wordTimer?.cancel();
    _tapSubs?.cancel(); // Hinzugefügt, um Tap-Abonnement zu beenden
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

        setState(() {
          // Text in Wörter aufteilen
          _words = _splitTextIntoWords(content);
          _currentWordIndex = _startWordIndex;
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
                if (_isPlaying) {
                  _pauseRSVP();
                } else {
                  _startRSVP();
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
    _words.clear();
    _stopRSVP();
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
    _keepAliveTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      if (frame != null) {
        try {
          await frame!
              .sendMessage(TxCode(msgCode: 0x11, value: 0)); // Keep-Alive-Nachricht
          _log.info('Keep-Alive-Nachricht an Frame gesendet.');
        } catch (e) {
          _log.warning('Fehler beim Senden der Keep-Alive-Nachricht: $e');
        }
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _startTapEnableTimer() {
    _tapEnableTimer = Timer.periodic(Duration(minutes: 1), (timer) async {
      if (frame != null) {
        try {
          await frame!
              .sendMessage(TxCode(msgCode: 0x10, value: 1)); // Tap-Ereignisse aktivieren
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

  List<String> _splitTextIntoWords(String text) {
    // Teilt den Text in Wörter und behält die Punctuation am Ende bei
    // Angepasste RegExp zur besseren Worttrennung inklusive deutscher Sonderzeichen
    RegExp exp = RegExp(r"([A-Za-zÄÖÜäöüß]+['-]?[A-Za-zÄÖÜäöüß]+[.,!?;]?)");
    Iterable<RegExpMatch> matches = exp.allMatches(text);
    return matches.map((m) => m.group(0)!).toList();
  }

  void _startRSVP() {
    if (_isPlaying) return;
    if (_currentWordIndex >= _words.length) {
      _currentWordIndex = _startWordIndex; // Startpunkt festlegen
    }
    _isPlaying = true;
    _log.info('RSVP gestartet.');
    _scheduleNextWord();
  }

  void _pauseRSVP() {
    _isPlaying = false;
    _wordTimer?.cancel();
    _wordTimer = null;
    _log.info('RSVP pausiert.');
  }

  void _stopRSVP() {
    _isPlaying = false;
    _wordTimer?.cancel();
    _wordTimer = null;
    _currentWordIndex = _startWordIndex; // Zurücksetzen auf Startpunkt
    _log.info('RSVP gestoppt.');
    _sendTextToFrame(clear: true);
  }

  void _scheduleNextWord() {
    if (!_isPlaying || _currentWordIndex >= _words.length) {
      _isPlaying = false;
      _log.info('RSVP beendet.');
      return;
    }

    String currentWord = _words[_currentWordIndex];
    _sendTextToFrame(text: currentWord, index: _currentWordIndex);

    // Bestimme die Verzögerung basierend auf Wortlänge und Punctuation
    double delaySeconds = _baseSpeed;

    if (currentWord.endsWith('.') ||
        currentWord.endsWith('!') ||
        currentWord.endsWith('?')) {
      delaySeconds *= 2.0; // Punctuation verlangsamt
    } else if (currentWord.length <= 3) {
      delaySeconds *= 0.75; // Kürzere Wörter beschleunigen
    }

    _wordTimer = Timer(Duration(milliseconds: (delaySeconds * 1000).toInt()),
        () {
      setState(() {
        _currentWordIndex++;
      });
      _scheduleNextWord();
    });
  }

  Future<void> _sendTextToFrame({String? text, bool clear = false, int? index}) async {
    try {
      if (frame == null) {
        _log.warning('Frame ist nicht verbunden.');
        return;
      }

      String displayText = clear
          ? ""
          : (text ?? ""); // Zeigt nur das aktuelle Wort oder leert das Display

      await frame!.sendMessage(TxPlainText(
        msgCode: 0x12,
        text: displayText,
      ));
      _log.info(
          'Nachricht an Frame gesendet: "${clear ? "Leeren Text gesendet" : displayText}"');

      // Optional: Weitere Logik, um den aktuellen Index auf dem Frame darzustellen
      // Dies hängt davon ab, wie das Frame die Informationen darstellt
    } catch (e) {
      _log.warning('Fehler beim Senden der Nachricht an das Frame: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Book Reader - RSVP',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Book Reader - RSVP'),
          actions: [getBatteryWidget()],
        ),
        body: Column(
          children: [
            Expanded(
              flex: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Tap-Handling für Play/Pause-Funktion auf dem Android-Gerät
                  setState(() {
                    if (_isPlaying) {
                      _pauseRSVP();
                    } else {
                      _startRSVP();
                    }
                  });
                },
                child: Center(
                  child: Text(
                    _isPlaying && _currentWordIndex < _words.length
                        ? _words[_currentWordIndex]
                        : '',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            Divider(),
            Expanded(
              flex: 3,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _words.length,
                itemBuilder: (context, index) {
                  bool isCurrent = index == _currentWordIndex;
                  bool isStart = index == _startWordIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _startWordIndex = index;
                        _currentWordIndex = _startWordIndex;
                        _pauseRSVP(); // Pause vor dem Setzen des Startpunkts
                        _log.info('Startwort gesetzt auf Index: $_startWordIndex');
                        _sendTextToFrame(text: _words[_currentWordIndex], index: _currentWordIndex);
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      color: isCurrent
                          ? Colors.yellow
                          : isStart
                              ? Colors.green[700]
                              : null,
                      child: Text(
                        _words[index],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              isCurrent || isStart ? FontWeight.bold : FontWeight.normal,
                          color:
                              isCurrent || isStart ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    setState(() {
                      if (_isPlaying) {
                        _pauseRSVP();
                      } else {
                        _startRSVP();
                      }
                    });
                  },
                ),
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      Slider(
                        value: _baseSpeed,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        label: 'Wortgeschwindigkeit',
                        onChanged: (value) {
                          setState(() {
                            _baseSpeed = value;
                            _log.info(
                                'RSVP-Geschwindigkeit geändert auf: $value s/Wort');
                          });
                        },
                      ),
                      // Entfernen des Sliders für MaxLinesOnScreen, da er nicht mehr benötigt wird
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
