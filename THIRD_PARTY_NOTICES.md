# Third-party components

The application depends on the exact packages in `pubspec.lock` and the native
libraries declared by their pinned releases. Flutter collects package notices for
the in-app license screen. Preserve those notices in distributed builds.

| Component | License / terms | Role |
| --- | --- | --- |
| Flutter and Dart | BSD-3-Clause | Application framework |
| paddle_ocr_native 0.1.1 | Apache-2.0 | Native Flutter OCR plugin and vendored PaddleOCR SDK |
| PaddleOCR / PP-OCRv6 small models | Apache-2.0 declared in package provenance / model cards | Bundled detection and recognition weights |
| ONNX Runtime | MIT | On-device inference |
| OpenCV | Apache-2.0 (Android 4.13), BSD-3-Clause (iOS 4.3) | OCR image processing |
| image | MIT | Image preprocessing |
| image_picker, path_provider | BSD-3-Clause | Platform image import and private directories |
| Google ML Kit Translation and Language Identification | Google API / ML Kit terms | Android on-device text processing |
| Apple Translation and NaturalLanguage | Apple platform SDK terms | iOS on-device text processing |

Model identities and checksums are recorded in `models.lock.json`. The sources are
[PP-OCRv6 small detection](https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx)
and [PP-OCRv6 small recognition](https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx).
The package's [provenance document](https://github.com/flespark/paddle_ocr_native/blob/main/doc/model-provenance.md)
records its upstream model declarations. Independently verify those model cards
and final binary notices before a public release.

Android translation attribution is shown alongside results and in Settings.
Review Google's [ML Kit translation usage guidelines](https://developers.google.com/ml-kit/language/translation/translation-terms)
before distribution. Offline translation is intended for casual text and may use
English as an intermediate language.
