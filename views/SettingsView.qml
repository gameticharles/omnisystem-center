import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// Every setting of the widget in one place, grouped, each with what it does.
// Built from the manifest's settings list; a change is written to the
// widget's entry in shell.json at once, as Omarchy's own settings page does.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim
  readonly property color accent: Model.tabTint("settings", panel.palette, String(Color.background))
  readonly property var sections: Model.settingSections(s.ownSchema)

  spacing: Style.space(14)

  Repeater {
    model: view.sections.length
    Section {
      id: sec
      required property int index
      readonly property var group: view.sections[index] || ({ title: "", schema: [] })
      title: group.title
      separator: index > 0
      foreground: view.fg
      fontFamily: view.ff

      SettingsForm {
        width: parent.width
        schema: sec.group.schema
        values: view.s.settings
        foreground: view.fg
        accent: view.accent
        fontFamily: view.ff
        panel: view.panel
        onChanged: function(key, value) {
          var patch = {}
          patch[key] = value
          view.s.updateBarSettings(patch)
        }
      }
    }
  }

  Section {
    title: "ENERGY METER"
    foreground: view.fg
    fontFamily: view.ff
    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "The electricity price, currency, the two estimates and sampling are kept by the meter itself and apply to all its history."
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
    }
    Button {
      text: "Open the energy settings"
      iconText: "󱐋"
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      fontSize: Style.font.caption
      onClicked: { view.s.energySettingsRequested = true; view.panel.tab = "energy" }
    }
  }
}
