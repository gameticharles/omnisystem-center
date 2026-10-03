import QtQuick
import Quickshell.Io

// One command, run once. Optional input goes to stdin, which is then closed,
// so payloads never travel in argv. Calls back with the exit code, stdout and
// stderr, then destroys itself. Created by Service.run().
Process {
  id: proc

  property string input: ""
  property bool hasInput: false
  property var callback: null

  property bool _exited: false
  property int _code: -1
  property bool _outDone: false
  property bool _errDone: false
  property bool _finished: false

  stdinEnabled: hasInput

  stdout: StdioCollector {
    waitForEnd: true
    onStreamFinished: { proc._outDone = true; proc._finish() }
  }
  stderr: StdioCollector {
    waitForEnd: true
    onStreamFinished: { proc._errDone = true; proc._finish() }
  }

  onStarted: {
    if (!hasInput) return
    write(input)
    input = ""
    stdinEnabled = false
  }

  onExited: function(exitCode) {
    _code = exitCode
    _exited = true
    _finish()
  }

  function _finish() {
    if (_finished || !_exited || !_outDone || !_errDone) return
    _finished = true
    var cb = callback
    callback = null
    if (typeof cb === "function") {
      try { cb(_code, String(stdout.text || ""), String(stderr.text || "")) } catch (e) { console.warn("omnisystem-center: callback failed:", e) }
    }
    Qt.callLater(function() { proc.destroy() })
  }
}
