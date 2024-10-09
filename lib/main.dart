import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/tx/text.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState {
  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  final List<String> _wrappedChunks = []; // Liste für umgebrochene Zeilen
  List<String> _visibleLines = [];
  int _currentLine = 0;
  bool _isTyping = false;
  double _typewriterSpeed = 0.03; // Sekunden pro Buchstabe
  int _currentCharIndex = 0;
  final int _maxLinesOnScreen = 4; // Maximal 4 Zeilen auf dem Bildschirm
  final int _chunkSize = 32; // Maximale Zeichenanzahl pro Zeile

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
        File file = File(result.files.single.path!);

        String content = await file.readAsString();
        _log.info('Dateiinhalt erfolgreich geladen.');

        _wrappedChunks.clear();
        setState(() {
          // Ersetze Zeilenumbrüche durch Leerzeichen, um den gesamten Text als einen Absatz zu behandeln
          String singleParagraph = content.replaceAll('\n', ' ');
          _wrappedChunks.addAll(_wrapTextToFit(singleParagraph, _chunkSize));
          _currentLine = 0;
          _currentCharIndex = 0;
          _visibleLines.clear();
        });

        _startTypewriterEffect();
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
    if (mounted) setState(() {});
  }

  void _startTypewriterEffect() {
    if (_isTyping) return; // Verhindere mehrfaches Starten
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

      for (; _currentCharIndex < wrappedLine.length; _currentCharIndex++) {
        if (!_isTyping) break;

        String char = wrappedLine[_currentCharIndex];
        _addCharacterToVisibleText(char);

        // Sende nach jedem Zeichen
        await _sendTextToFrame();

        // Verzögerung basierend auf der Typewriter-Geschwindigkeit
        await Future.delayed(Duration(
            milliseconds: (_typewriterSpeed * 1000).toInt()));
      }

      if (!_isTyping) break;

      // Nach vollständiger Verarbeitung einer Zeile
      _currentCharIndex = 0;
      _currentLine++;

      // Scrollen, wenn zu viele Zeilen vorhanden sind
      if (_visibleLines.length > _maxLinesOnScreen) {
        _visibleLines.removeAt(0);
        _log.info('Entferne oberste Zeile, um zu scrollen.');
      }

      setState(() {}); // Update die UI

      // Kurze Pause zwischen den Zeilen
      await Future.delayed(Duration(milliseconds: 100));
    }

    _isTyping = false;
    _log.info('Typewriter-Effekt abgeschlossen.');
  }

  // Optimierte Textumbruch-Funktion basierend auf Wortgrenzen
  List<String> _wrapTextToFit(String text, int maxCharsPerLine) {
    List<String> lines = [];
    List<String> words = text.split(RegExp(r'\s+')); // Splitte anhand von Leerzeichen
    String currentLine = '';

    for (String word in words) {
      word = word.trim();

      if (word.isEmpty) continue;

      // Berechne die potenzielle Länge der aktuellen Zeile nach Hinzufügen des Wortes
      int prospectiveLength = currentLine.isEmpty ? word.length : currentLine.length + 1 + word.length;

      if (prospectiveLength <= maxCharsPerLine) {
        // Füge das Wort zur aktuellen Zeile hinzu
        currentLine += (currentLine.isEmpty ? '' : ' ') + word;
      } else {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
        }

        // Wenn das Wort selbst länger ist als maxCharsPerLine, splitte es
        if (word.length > maxCharsPerLine) {
          int start = 0;
          while (start < word.length) {
            int end = (start + maxCharsPerLine) < word.length ? start + maxCharsPerLine : word.length;
            lines.add(word.substring(start, end));
            start += maxCharsPerLine;
          }
          currentLine = '';
        } else {
          // Beginne eine neue Zeile mit dem aktuellen Wort
          currentLine = word;
        }
      }
    }

    // Füge die letzte Zeile hinzu, falls vorhanden
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }

  Future<void> _sendTextToFrame() async {
    try {
      if (frame == null) {
        _log.warning('Frame ist nicht verbunden.');
        return;
      }

      // Verbinde die sichtbaren Zeilen und sende sie als Ganzes
      String fullText = _visibleLines.join('\n');

      // Verhindere das Senden leerer Nachrichten
      if (fullText.trim().isEmpty) {
        _log.warning('Leere Nachricht wird nicht gesendet.');
        return;
      }

      // Sende die aktuelle sichtbare Textmenge
      await frame!.sendMessage(TxPlainText(
        msgCode: 0x0a,
        text: fullText, // Sende den gesamten sichtbaren Text
      ));
      _log.info('Nachricht an Frame gesendet: "$fullText"');
    } catch (e) {
      _log.warning('Fehler beim Senden der Nachricht an das Frame: $e');
    }
  }

  void _addCharacterToVisibleText(String char) {
    // Füge ein neues Zeichen zur aktuellen Zeile hinzu
    if (_currentCharIndex == 0) {
      _visibleLines.add(char);
    } else {
      _visibleLines[_visibleLines.length - 1] += char;
    }
    // Kein setState hier notwendig, da wir nur beim Senden aktualisieren
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Teleprompter',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Teleprompter'),
          actions: [getBatteryWidget()],
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (x) async {
            // Scroll-Handling
          },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  _visibleLines.isNotEmpty
                      ? _visibleLines.join('\n')
                      : 'Laden Sie eine Datei',
                  style: const TextStyle(
                    fontSize: 24,
                    fontFamily: 'Courier', // Feste Schriftart für Konsistenz
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(
            const Icon(Icons.file_open), const Icon(Icons.close)),
        persistentFooterButtons: [
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
            child: Slider(
              value: _typewriterSpeed,
              min: 0.03, // Angepasst auf 0.03 Sekunden als Minimalwert
              max: 0.2,
              divisions: 17, // Angepasst basierend auf dem neuen Bereich
              label: '${_typewriterSpeed.toStringAsFixed(2)} s/Buchstabe',
              onChanged: (value) {
                setState(() {
                  _typewriterSpeed = value;
                  _log.info('Typewriter-Geschwindigkeit geändert auf: $value s/Buchstabe');
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
