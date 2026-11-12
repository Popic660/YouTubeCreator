import QtQuick
import QtQuick.Controls

Item {
   id: wrap
   property string toolName: ""
   property bool toolsEnabled: false
   width: Theme.buttonHeight
   height: Theme.buttonHeight
   property alias iconColor: tool.iconColor
   property alias radius: tool.radius
   property alias glyphSignature: tool.glyphSignature
   property alias hint: tool.hint
   property alias enabled: tool.enabled
   signal activated(string name)

   ToolButton {
      id: tool
      objectName: wrap.toolName
      property string toolName: wrap.toolName
      anchors.fill: parent
      enabled: wrap.toolsEnabled
      padding: 0
      hoverEnabled: true
      property color iconColor: enabled ? Theme.text : Theme.textDisabled
      property int radius: Theme.buttonRadius
      property string glyphSignature: mark.signature
      property string hint: wrap.hintFor(wrap.toolName)
      background: Rectangle {
         radius: tool.radius
         color: Theme.faceTonal(tool.hovered || hover.hovered, tool.down)
      }
      contentItem: Glyph {
         id: mark
         glyphName: tool.toolName
         strokeColor: tool.iconColor
      }
      onClicked: wrap.activated(wrap.toolName)
   }

   HoverHandler {
      id: hover
   }
   HintTip {
      visible: hover.hovered && tool.hint.length > 0
      text: tool.hint
   }

   function hintFor(name) {
      const hints = {
         "toolSelect":
            "Выбор клипа. Нажмите, когда ролик уже на таймлайне: " +
            "выделится видео на дорожке V1 (синяя обводка блока). " +
            "Дальше его можно резать, двигать кадр или удалить " +
            "корзиной справа. Это не удаляет ролик из папки слева. " +
            "Пока клипов нет, кнопка серая — сначала «⋯» у папки → " +
            "«Импорт видео».",
         "toolRazor":
            "Лезвие — режет клип по красной линии (playhead). " +
            "Как работать: 1) кликните по дорожке там, где нужен рез; " +
            "2) нажмите лезвие. Если линия в самом начале или конце, " +
            "сначала она встанет на середину, потом разрежет. " +
            "Получатся два куска на той же дорожке. То же действие — " +
            "кнопка «разделить» справа.",
         "toolHand":
            "Сдвиг кадра внутри 9:16. Каждый клик двигает картинку " +
            "вправо на 12 пикселей. Нужно, если лицо или объект не " +
            "по центру вертикального кадра. Повторяйте клик, пока " +
            "кадр не встанет. Вернуть как было: кнопка кадрирования " +
            "(рамка) справа — сброс зума и сдвига.",
         "toolText":
            "Текст на дорожку V2. Кладёт заготовку «Текст» поверх " +
            "видео: на таймлайне появится блок V2. Это ещё не " +
            "полноценный редактор надписи, а слой-заготовка. Убрать " +
            "слой: выделите его кликом по блоку V2 и нажмите корзину.",
         "toolZoom":
            "Масштаб кадра ×1.25 за клик. Увеличивает картинку внутри " +
            "9:16 — так горизонтальный исходник заполняет вертикаль " +
            "без чёрных полос. Повторите для большего зума. Сброс — " +
            "кнопка кадрирования справа.",
         "opSplit":
            "Разделить клип по красной линии. Сначала кликните " +
            "таймлайн в точке реза (линия едет за курсором), потом " +
            "эту кнопку. Если линия в начале или конце ролика, рез " +
            "пойдёт с середины. То же, что лезвие слева.",
         "opCrop":
            "Вписать в 9:16. Сбрасывает зум и сдвиг: кадр снова " +
            "покрывает весь вертикальный прямоугольник (cover), без " +
            "чёрных полей. Нажмите, если рука или масштаб уехали.",
         "opTransform":
            "Пресет кадра: масштаб 1.2 и сдвиг 8×8 (чуть крупнее и " +
            "правее-ниже). Один клик — готовая рамка. Для шагов " +
            "пользуйтесь рукой и зумом слева, для сброса — " +
            "кадрированием.",
         "opVolume":
            "Громкость дорожки A1. Один клик ставит 40% — если " +
            "исходник слишком громкий. Ползунка громкости пока нет. " +
            "Звук превью берётся с A1; без блока A1 будет тихо.",
         "opDelete":
            "Удалить клип с таймлайна, не ролик из папки. Сначала " +
            "кликните блок на дорожке (или «выбор»), потом корзину. " +
            "Если ничего не выделено, снимается первый клип V1. " +
            "Файл в библиотеке останется. Чтобы убрать сам ролик из " +
            "папки — ПКМ по превью слева или «Удалить» в шапке «Папки»."
      }
      return hints[name] || ""
   }
}
