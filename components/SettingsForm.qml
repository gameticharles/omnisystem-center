import QtQuick
import qs.Ui
import qs.Commons

// A form from a manifest's `barWidget.schema`: each entry gets its label, its
// description and a control for its type (a switch, a row of choices, a
// number, text, or JSON for an object). `values` holds what is set now;
// `changed(key, value)` fires once per edit, and the owner writes it.
Column {
  id: form

  property var schema: []
  property var values: ({})
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property var panel: null
  signal changed(string key, var value)

  function current(entry) {
    var v = values ? values[entry.key] : undefined
    return v === undefined || v === null ? entry.defaultValue : v
  }

  spacing: Style.space(12)

  Repeater {
    model: (form.schema || []).length
    Column {
      id: field
      required property int index
      readonly property var entry: (form.schema || [])[index] || ({})
      readonly property var value: form.current(entry)
      width: form.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: Math.max(fieldLabel.implicitHeight, control.implicitHeight)
        Text {
          id: fieldLabel
          anchors.left: parent.left
          anchors.right: control.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: field.entry.label || field.entry.key
          color: form.foreground
          font.family: form.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.WordWrap
        }
        Loader {
          id: control
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          sourceComponent: field.entry.type === "boolean" ? switchControl
                         : field.entry.type === "integer" || field.entry.type === "number" ? numberControl
                         : null
        }
      }

      // Choices: a row of buttons under the label.
      Flow {
        visible: field.entry.type === "enum"
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: field.entry.type === "enum" ? field.entry.options || [] : []
          Button {
            required property var modelData
            readonly property bool on: String(field.value) === String(modelData)
            text: String(modelData)
            bordered: true
            foreground: on ? form.accent : Qt.darker(form.foreground, 1.3)
            background: on ? Qt.rgba(form.accent.r, form.accent.g, form.accent.b, 0.14) : "transparent"
            accent: form.accent
            fontFamily: form.fontFamily
            fontSize: Style.font.caption
            verticalPadding: Style.space(3)
            onClicked: if (!on) form.changed(field.entry.key, modelData)
          }
        }
      }

      // Text, or an object as JSON: saved on Enter or when the field is left.
      TextField {
        id: textField
        visible: field.entry.type === "string" || field.entry.type === "object" || field.entry.type === "array"
        width: parent.width
        readonly property bool json: field.entry.type === "object" || field.entry.type === "array"
        readonly property string shown: json ? JSON.stringify(field.value === undefined ? (field.entry.type === "array" ? [] : {}) : field.value)
                                             : String(field.value === undefined ? "" : field.value)
        text: shown
        foreground: form.foreground
        accent: form.accent
        font.family: form.fontFamily
        font.pixelSize: Style.font.caption
        onActiveFocusChanged: {
          if (form.panel) form.panel.textEditing = activeFocus
          if (!activeFocus) save()
        }
        onAccepted: save()
        function save() {
          if (text === shown) return
          if (!json) { form.changed(field.entry.key, text); return }
          try { form.changed(field.entry.key, JSON.parse(text)) } catch (e) { text = shown }
        }
      }

      Text {
        visible: !!field.entry.description
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: field.entry.description || ""
        color: Qt.darker(form.foreground, 1.4)
        font.family: form.fontFamily
        font.pixelSize: Style.font.caption
      }

      Component {
        id: switchControl
        ToggleSwitch {
          checked: field.value === true
          foreground: form.foreground
          accent: form.accent
          onToggled: if (field.entry) form.changed(field.entry.key, !(field.value === true))
        }
      }
      Component {
        id: numberControl
        NumberField {
          readonly property var e: field.entry || ({})
          value: Number(field.value) || 0
          from: e.min !== undefined ? e.min : 0
          to: e.max !== undefined ? e.max : 100000
          stepSize: e.step || 1
          foreground: form.foreground
          accent: form.accent
          fontFamily: form.fontFamily
          fontSize: Style.font.caption
          onModified: function(v) { if (field.entry && v !== Number(field.value)) form.changed(field.entry.key, v) }
        }
      }
    }
  }
}
