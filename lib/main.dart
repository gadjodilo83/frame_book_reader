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

  final List<String> _textChunks = [];
  final List<String> _wrappedChunks = []; // Neue Liste für umgebrochene Zeilen
  List<String> _visibleLines = [];
  int _currentLine = 0;
  bool _isTyping = false;
  double _typewriterSpeed = 0.01; // Sekunden pro Buchstabe (angepasst)
  int _currentCharIndex = 0;
  final int _maxLinesOnScreen = 4; // Maximal 4 Zeilen auf dem Bildschirm
  final int _chunkSize = 64; // Maximale Zeichenanzahl pro Chunk

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
        _textChunks.clear();
        _wrappedChunks.clear(); // Leere die umgebrochenen Zeilen
        setState(() {
          _textChunks.addAll(content.split('\n'));
          for (String chunk in _textChunks) {
            _wrappedChunks.addAll(_wrapTextToFit(chunk, 30));
          }
          _currentLine = 0;
          _currentCharIndex = 0;
          _visibleLines.clear(); // Leere die sichtbaren Zeilen
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
    _textChunks.clear();
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
      _log.info('Verarbeite Zeile $_currentLine: $wrappedLine');

      for (; _currentCharIndex < wrappedLine.length; _currentCharIndex++) {
        if (!_isTyping) break;

        String char = wrappedLine[_currentCharIndex];
        _addCharacterToVisibleText(char);
        _log.info('Füge Zeichen hinzu: $char');

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
      await Future.delayed(Duration(milliseconds: 10));
    }

    _isTyping = false;
    _log.info('Typewriter-Effekt abgeschlossen.');
  }

  // Verbessertes Wrap-Text zu Zeilen basierend auf Wortgrenzen
  List<String> _wrapTextToFit(String text, int maxCharsPerLine) {
    List<String> lines = [];
    List<String> words = text.split(' ');
    String currentLine = '';

    for (String word in words) {
      if (word.length > maxCharsPerLine) {
        // Wenn ein Wort länger ist als maxCharsPerLine, splitte es
        while (word.length > maxCharsPerLine) {
          String part = word.substring(0, maxCharsPerLine);
          lines.add(part);
          word = word.substring(maxCharsPerLine);
        }
        if (word.isNotEmpty) {
          if ((currentLine.length + word.length + (currentLine.isEmpty ? 0 : 1)) <= maxCharsPerLine) {
            currentLine += (currentLine.isEmpty ? '' : ' ') + word;
          } else {
            if (currentLine.isNotEmpty) {
              lines.add(currentLine);
            }
            currentLine = word;
          }
        }
      } else {
        if ((currentLine.length + word.length + (currentLine.isEmpty ? 0 : 1)) <= maxCharsPerLine) {
          currentLine += (currentLine.isEmpty ? '' : ' ') + word;
        } else {
          if (currentLine.isNotEmpty) {
            lines.add(currentLine);
          }
          currentLine = word;
        }
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    _log.info('Umgebrochene Zeilen: ${lines.join(', ')}');
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
      _log.info('Nachricht an Frame gesendet: $fullText');

      // Keine zusätzliche Verzögerung hier, da die Schleife bereits eine Verzögerung hat
    } catch (e) {
      _log.warning('Fehler beim Senden der Nachricht an das Frame: $e');
    }
  }

  void _addCharacterToVisibleText(String char) {
    // Füge ein neues Zeichen zur aktuellen Zeile hinzu
    if (_currentCharIndex == 0) {
      _visibleLines.add(char);
      _log.info('Neue Zeile hinzugefügt: $char');
    } else {
      _visibleLines[_visibleLines.length - 1] += char;
      _log.info('Zeichen zur aktuellen Zeile hinzugefügt: $char');
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
                  style: const TextStyle(fontSize: 24),
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
              min: 0.005, // Angepasst auf 0.02 für bessere Balance
              max: 0.2,
              divisions: 18,
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
