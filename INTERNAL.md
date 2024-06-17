Please put libraries here by using release script.

ailia/android/src/main/jniLibs/arm64-v8a/libailia.so
ailia/android/src/main/jniLibs/arm64-v8a/libailia_audio.so
ailia/example/assets/resnet18.onnx
ailia/ios/libailia.a
ailia/ios/libailia_audio.a
ailia/macos/libailia.dylib
ailia/macos/libailia_audio.dylib
ailia/macos/libailia_blas.dylib
ailia/macos/libailia_pose_estimate.dylib

Please put interface here.

native/ailia.h
native/ailia_classifier.h
native/ailia_detector.h
native/ailia_feature_extractor.h
native/ailia_format.h
native/ailia_pose_estimator.h

Please run below command for generation.

dart run ffigen --config ffigen_ailia.yaml
