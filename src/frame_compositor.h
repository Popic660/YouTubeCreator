#pragma once

#include "project_document.h"

#include <QImage>
#include <QQuickItem>
#include <QQuickPaintedItem>
#include <QString>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Собирает кадр 9:16 в позиции ползунка.
 */
class CFrameCompositor : public QQuickPaintedItem {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CProjectDocument* document READ document WRITE set_document
                  NOTIFY document_changed)
   Q_PROPERTY(QImage preview READ preview NOTIFY frame_changed)
   Q_PROPERTY(bool hasFrame READ has_frame NOTIFY frame_changed)
   Q_PROPERTY(int previewWidth READ preview_width NOTIFY frame_changed)
   Q_PROPERTY(int previewHeight READ preview_height NOTIFY frame_changed)
   Q_PROPERTY(bool leftEdgeOpaque READ left_edge_opaque
                  NOTIFY frame_changed)
   Q_PROPERTY(qint64 lastSourceMs READ last_source_ms
                  NOTIFY frame_changed)

 public:
   static constexpr int kPreviewWidth = 90;
   static constexpr int kPreviewHeight = 160;
   static constexpr int kExportWidth = 1080;
   static constexpr int kExportHeight = 1920;

   /**
    * @brief Создаёт компоновщик.
    * @param parent - владелец.
    */
   explicit CFrameCompositor(QQuickItem* parent = nullptr);

   /**
    * @brief Рисует превью.
    * @param painter - холст Qt Quick.
    */
   void paint(QPainter* painter) override;

   CProjectDocument* document() const { return document_; }
   /**
    * @brief Подключает документ.
    * @param document - проект ролика.
    */
   void set_document(CProjectDocument* document);

   QImage preview() const { return preview_; }
   bool has_frame() const { return has_frame_; }
   int preview_width() const { return preview_.width(); }
   int preview_height() const { return preview_.height(); }
   bool left_edge_opaque() const { return left_edge_opaque_; }
   qint64 last_source_ms() const { return last_source_ms_; }

   /**
    * @brief Собирает кадр для экспорта.
    * @param time_ms - время таймлайна.
    * @return картинка 1080×1920.
    */
   QImage compose_export(qint64 time_ms);

   /**
    * @brief Обновляет превью текущего ползунка.
    */
   Q_INVOKABLE void refresh();

 signals:
   void document_changed();
   void frame_changed();

 private:
   QImage compose(qint64 time_ms, int width, int height);
   void connect_document();

   CProjectDocument* document_ = nullptr;
   QImage preview_;
   bool has_frame_ = false;
   bool left_edge_opaque_ = false;
   qint64 last_source_ms_ = 0;
};
