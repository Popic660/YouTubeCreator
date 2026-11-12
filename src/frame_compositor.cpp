#include "frame_compositor.h"

#include "media_io.h"

#include <QColor>
#include <QFont>
#include <QPainter>
#include <QRect>

#include <algorithm>

CFrameCompositor::CFrameCompositor(QQuickItem* parent)
    : QQuickPaintedItem(parent) {
   setOpaquePainting(true);
   setAcceptedMouseButtons(Qt::NoButton);
}

void CFrameCompositor::set_document(CProjectDocument* document) {
   if (document_ == document) {
      return;
   }
   if (document_ != nullptr) {
      disconnect(document_, nullptr, this, nullptr);
   }
   document_ = document;
   connect_document();
   refresh();
   emit document_changed();
}

void CFrameCompositor::connect_document() {
   if (document_ == nullptr) {
      return;
   }
   connect(document_, &CProjectDocument::timeline_changed, this,
           &CFrameCompositor::refresh);
   connect(document_, &CProjectDocument::playhead_changed, this,
           &CFrameCompositor::refresh);
   connect(document_, &CProjectDocument::short_changed, this,
           &CFrameCompositor::refresh);
}

QImage CFrameCompositor::compose_export(qint64 time_ms) {
   return compose(time_ms, kExportWidth, kExportHeight);
}

void CFrameCompositor::refresh() {
   last_source_ms_ = 0;
   left_edge_opaque_ = false;
   if (document_ == nullptr || !document_->has_clips()) {
      preview_ = {};
      has_frame_ = false;
      emit frame_changed();
      return;
   }
   preview_ = compose(document_->playhead_ms(), kPreviewWidth,
                      kPreviewHeight);
   has_frame_ = !preview_.isNull();
   if (has_frame_) {
      left_edge_opaque_ = true;
      for (int y = 0; y < preview_.height(); ++y) {
         if (qAlpha(preview_.pixel(0, y)) < 255) {
            left_edge_opaque_ = false;
            break;
         }
      }
   }
   emit frame_changed();
   update();
}

void CFrameCompositor::paint(QPainter* painter) {
   painter->fillRect(boundingRect(), QColor("#0f0f0f"));
   if (!has_frame_ || preview_.isNull()) {
      return;
   }
   painter->drawImage(boundingRect(), preview_);
}

QImage CFrameCompositor::compose(qint64 time_ms, int width,
                                 int height) {
   QImage canvas(width, height, QImage::Format_ARGB32);
   canvas.fill(QColor(0, 0, 0, 255));
   if (document_ == nullptr) {
      return canvas;
   }
   const TimelineClip* video = document_->video_at(time_ms);
   if (video != nullptr) {
      const qint64 source =
          video->in_ms + (time_ms - video->start_ms);
      last_source_ms_ = source;
      const QImage frame =
          CMediaIo::decode_frame(document_->clip_abs_path(video->id),
                                 source);
      if (!frame.isNull()) {
         const double canvas_ratio =
             static_cast<double>(width) / height;
         const double frame_ratio =
             static_cast<double>(frame.width()) / frame.height();
         double cover = 1.0;
         if (frame_ratio > canvas_ratio) {
            cover = static_cast<double>(height) / frame.height();
         } else {
            cover = static_cast<double>(width) / frame.width();
         }
         const double scale = cover * video->scale;
         const int draw_w =
             static_cast<int>(frame.width() * scale);
         const int draw_h =
             static_cast<int>(frame.height() * scale);
         const int x = (width - draw_w) / 2 +
                       static_cast<int>(video->offset_x);
         const int y = (height - draw_h) / 2 +
                       static_cast<int>(video->offset_y);
         QPainter painter(&canvas);
         painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
         painter.drawImage(QRect(x, y, draw_w, draw_h), frame);
      }
   }
   const auto overlays = document_->overlays_at(time_ms);
   if (!overlays.empty()) {
      QPainter painter(&canvas);
      painter.setPen(QColor("#f1f1f1"));
      QFont font("Roboto");
      font.setPixelSize(std::max(16, height / 18));
      font.setWeight(QFont::Medium);
      painter.setFont(font);
      for (const TimelineClip* overlay : overlays) {
         if (overlay->kind == QLatin1String("text")) {
            painter.drawText(canvas.rect(), Qt::AlignCenter,
                             overlay->text);
         }
      }
   }
   return canvas;
}
