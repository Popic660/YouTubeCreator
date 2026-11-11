import QtQuick
import QtQuick.Shapes

// Контуры Lucide (ISC): https://lucide.dev
Item {
   id: glyph
   property string glyphName: ""
   property color strokeColor: "#717171"
   readonly property string signature: commands(glyphName)

   Shape {
      anchors.centerIn: parent
      width: 24
      height: 24
      antialiasing: true

      ShapePath {
         strokeColor: glyph.strokeColor
         strokeWidth: 2
         fillColor: "transparent"
         capStyle: ShapePath.RoundCap
         joinStyle: ShapePath.RoundJoin
         PathSvg { path: glyph.signature }
      }
   }

   function commands(name) {
      const paths = {
         "toolSelect": "M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z",
         "toolRazor": "M11 16.586V19a1 1 0 0 1-1 1H2L18.37 3.63a1 1 0 1 1 3 3l-9.663 9.663a1 1 0 0 1-1.414 0L8 14",
         "toolHand": "M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2 M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2 M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8 M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15",
         "toolText": "M12 4v16 M4 7V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v2 M9 20h6",
         "toolZoom": "M3 11 A8 8 0 1 1 19 11 A8 8 0 1 1 3 11 M21 21 L16.65 16.65 M11 8 L11 14 M8 11 L14 11",
         "opSplit": "M3 6 A3 3 0 1 1 9 6 A3 3 0 1 1 3 6 M8.12 8.12 L12 12 M20 4 L8.12 15.88 M3 18 A3 3 0 1 1 9 18 A3 3 0 1 1 3 18 M14.8 14.8 L20 20",
         "opCrop": "M6 2v14a2 2 0 0 0 2 2h14 M18 22V8a2 2 0 0 0-2-2H2",
         "opTransform": "M12 2v20 M15 19l-3 3l-3-3 M19 9l3 3l-3 3 M2 12h20 M5 9l-3 3l3 3 M9 5l3-3l3 3",
         "opVolume": "M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z M16 9a5 5 0 0 1 0 6 M19.364 18.364a9 9 0 0 0 0-12.728",
         "opDelete": "M10 11v6 M14 11v6 M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6 M3 6h18 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2",
         "channelMenu": "M2 12 A10 10 0 1 1 22 12 A10 10 0 1 1 2 12 M9 10 A3 3 0 1 1 15 10 A3 3 0 1 1 9 10 M7 20.662V19a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v1.662"
      }
      return paths[name] || ""
   }
}
