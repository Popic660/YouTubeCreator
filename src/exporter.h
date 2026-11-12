#pragma once

#include "frame_compositor.h"
#include "project_document.h"

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

/**
 * @brief Пишет вертикальный mp4 из документа.
 */
class CExporter : public QObject {
   Q_OBJECT
   QML_ELEMENT
   Q_PROPERTY(CProjectDocument* document READ document WRITE set_document
                  NOTIFY document_changed)
   Q_PROPERTY(CFrameCompositor* compositor READ compositor
                  WRITE set_compositor NOTIFY compositor_changed)
   Q_PROPERTY(QString lastPath READ last_path NOTIFY finished)
   Q_PROPERTY(QString lastError READ last_error NOTIFY finished)
   Q_PROPERTY(int lastWidth READ last_width NOTIFY finished)
   Q_PROPERTY(int lastHeight READ last_height NOTIFY finished)

 public:
   /**
    * @brief Создаёт экспортёр.
    * @param parent - владелец.
    */
   explicit CExporter(QObject* parent = nullptr);

   CProjectDocument* document() const { return document_; }
   CFrameCompositor* compositor() const { return compositor_; }
   QString last_path() const { return last_path_; }
   QString last_error() const { return last_error_; }
   int last_width() const { return last_width_; }
   int last_height() const { return last_height_; }

   /**
    * @brief Подключает документ.
    * @param document - проект.
    */
   void set_document(CProjectDocument* document);

   /**
    * @brief Подключает компоновщик.
    * @param compositor - кадр.
    */
   void set_compositor(CFrameCompositor* compositor);

   /**
    * @brief Собирает mp4 в exports/.
    * @return путь файла или пусто.
    */
   Q_INVOKABLE QString export_current();

 signals:
   void document_changed();
   void compositor_changed();
   void finished();

 private:
   CProjectDocument* document_ = nullptr;
   CFrameCompositor* compositor_ = nullptr;
   QString last_path_;
   QString last_error_;
   int last_width_ = 0;
   int last_height_ = 0;
};
