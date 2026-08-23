import 'handlers/document_handlers.dart';
import 'handlers/ocr_extract_text_handler.dart';
import 'handlers/lightweight_vision_handlers.dart';
import 'handlers/task_handler.dart';
import 'handlers/vision_handlers.dart';

class MobileTaskDispatcher {
  MobileTaskDispatcher({List<TaskHandler>? handlers})
    : _handlers = handlers ?? _defaultHandlers;

  final List<TaskHandler> _handlers;

  static final _defaultHandlers = <TaskHandler>[
    OcrExtractTextHandler(),
    DocumentExtractHandler(),
    DocumentClassifyHandler(),
    DocumentSummarizeHandler(),
    TextClassifyHandler(),
    DocumentImageQualityHandler(),
    BlurryImageHandler(),
    DuplicateImageHandler(),
    VisionAnalyzeHandler(),
    RemoveBackgroundHandler(),
  ];

  TaskHandler? handlerFor(String v1Type) {
    for (final handler in _handlers) {
      if (handler.capability == v1Type) {
        return handler;
      }
    }
    return null;
  }

  Iterable<String> get capabilities => _handlers.map((h) => h.capability);
}
