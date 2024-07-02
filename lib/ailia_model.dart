// ailia SDK Utility Class

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'ailia.dart' as ailia_dart;

class AiliaDetail {
  String name = "";
  AiliaShape shape = AiliaShape();
}

class AiliaShape {
  int x = 0;
  int y = 0;
  int z = 0;
  int w = 0;
  int dim = 0;
}

class AiliaTensor {
  AiliaShape shape = AiliaShape();
  Float32List data = Float32List(0);
}

class AiliaEnvironment {
  int id = 0;
  int props = 0;
  String name = "";
}

class AiliaDetectorObject {
  double x = 0;
  double y = 0;
  double w = 0;
  double h = 0;
  int category = 0;
  double prob = 0;
}

class AiliaModel {
  Pointer<Pointer<ailia_dart.AILIANetwork>>? ppAilia;
  dynamic ailia;
  bool _available = false;

  static String _ailiaCommonGetPath() {
    if (Platform.isAndroid || Platform.isLinux) {
      return 'libailia.so';
    }
    if (Platform.isMacOS) {
      return 'libailia.dylib';
    }
    if (Platform.isWindows) {
      return 'ailia.dll';
    }
    return 'internal';
  }

  static DynamicLibrary _ailiaCommonGetLibrary(String path) {
    final DynamicLibrary library;
    if (Platform.isIOS) {
      library = DynamicLibrary.process();
    } else {
      library = DynamicLibrary.open(path);
    }
    return library;
  }

  void _open(int envId, int memoryMode) {
    ailia = ailia_dart.ailiaFFI(_ailiaCommonGetLibrary(_ailiaCommonGetPath()));
    ppAilia = malloc<Pointer<ailia_dart.AILIANetwork>>();

    int status = ailia.ailiaCreate(
      ppAilia,
      envId,
      ailia_dart.AILIA_MULTITHREAD_AUTO,
    );
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaCreate failed $status");
    }

    status = ailia.ailiaSetMemoryMode(ppAilia!.value, memoryMode);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaCreate failed $status");
    }
  }

  void openFile(String onnxPath,
      {int envId = ailia_dart.AILIA_ENVIRONMENT_ID_AUTO,
      int memoryMode = ailia_dart.AILIA_MEMORY_OPTIMAIZE_DEFAULT}) {
    close();

    _open(envId, memoryMode);

    int status;
    if (Platform.isWindows) {
      status = ailia.ailiaOpenWeightFileW(
        ppAilia!.value,
        onnxPath.toNativeUtf16().cast<Int16>(),
      );
    } else {
      status = ailia.ailiaOpenWeightFileA(
        ppAilia!.value,
        onnxPath.toNativeUtf8().cast<Int8>(),
      );
    }
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaOpenWeightFile failed $status $onnxPath");
    }
    _available = true;
  }

  void openMem(Uint8List onnx,
      {int envId = ailia_dart.AILIA_ENVIRONMENT_ID_AUTO,
      int memoryMode = ailia_dart.AILIA_MEMORY_OPTIMAIZE_DEFAULT}) {
    close();

    _open(envId, memoryMode);

    Pointer<Uint8> onnxModel = malloc<Uint8>(onnx.length);
    for (int i = 0; i < onnx.length; i++) {
      onnxModel[i] = onnx[i];
    }

    int status =
        ailia.ailiaOpenWeightMem(ppAilia!.value, onnxModel, onnx.length);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaOpenWeightMem failed $status");
    }
    malloc.free(onnxModel);

    _available = true;
  }

  Float32List _toList(Pointer<Float> tensorData, int tensorSize) {
    Float32List floatData = Float32List(tensorSize);
    for (int j = 0; j < tensorSize; j++) {
      floatData[j] = tensorData[j];
    }
    return floatData;
  }

  List<AiliaTensor> run(List<AiliaTensor> inputTensor) {
    for (int i = 0; i < inputTensor.length; i++) {
      AiliaTensor tensor = inputTensor[i];
      Pointer<ailia_dart.AILIAShape> inputBlobShape =
          malloc<ailia_dart.AILIAShape>();
      inputBlobShape.ref.x = tensor.shape.x;
      inputBlobShape.ref.y = tensor.shape.y;
      inputBlobShape.ref.z = tensor.shape.z;
      inputBlobShape.ref.w = tensor.shape.w;
      inputBlobShape.ref.dim = tensor.shape.dim;

      final Pointer<Uint32> inputBlobIdx = malloc<Uint32>();
      inputBlobIdx.value = 0;
      int status = ailia.ailiaGetBlobIndexByInputIndex(
        ppAilia!.value,
        inputBlobIdx,
        i,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobIndexByInputIndex error $status");
      }
      status = ailia.ailiaSetInputBlobShape(
        ppAilia!.value,
        inputBlobShape,
        inputBlobIdx.value,
        ailia_dart.AILIA_SHAPE_VERSION,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaSetInputBlobShape error $status");
      }

      Pointer<Float> inputData = malloc<Float>(tensor.data.length);
      for (int j = 0; j < tensor.data.length; j++) {
        inputData[j] = tensor.data[j];
      }

      status = ailia.ailiaSetInputBlobData(ppAilia!.value,
          inputData.cast<Void>(), tensor.data.length * 4, inputBlobIdx.value);
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaSetInputBlobData error $status");
      }
      malloc.free(inputBlobIdx);
      malloc.free(inputBlobShape);
      malloc.free(inputData);
    }

    int status = ailia.ailiaUpdate(ppAilia!.value);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaUpdate error $status");
    }

    final Pointer<Uint32> outputBlobCnt = malloc<Uint32>();
    outputBlobCnt.value = 0;
    status = ailia.ailiaGetOutputBlobCount(ppAilia!.value, outputBlobCnt);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaGetOutputBlobCount error $status");
    }

    List<AiliaTensor> outputTensor = List<AiliaTensor>.empty(growable: true);
    for (int i = 0; i < outputBlobCnt.value; i++) {
      Pointer<ailia_dart.AILIAShape> outputBlobShape =
          malloc<ailia_dart.AILIAShape>();
      final Pointer<Uint32> outputBlobIdx = malloc<Uint32>();
      outputBlobIdx.value = 0;
      status = ailia.ailiaGetBlobIndexByOutputIndex(
        ppAilia!.value,
        outputBlobIdx,
        i,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobIndexByOutputIndex error $status");
      }
      status = ailia.ailiaGetBlobShape(
        ppAilia!.value,
        outputBlobShape,
        outputBlobIdx.value,
        ailia_dart.AILIA_SHAPE_VERSION,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobShape error $status");
      }
      int size = outputBlobShape.ref.x *
          outputBlobShape.ref.y *
          outputBlobShape.ref.z *
          outputBlobShape.ref.w;
      Pointer<Float> embedding = malloc<Float>(size);
      status = ailia.ailiaGetBlobData(
        ppAilia!.value,
        embedding.cast<Void>(),
        size * 4,
        outputBlobIdx.value,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobData error $status");
      }

      Float32List data = _toList(embedding, size);
      AiliaTensor tensor = AiliaTensor();
      tensor.shape.x = outputBlobShape.ref.x;
      tensor.shape.y = outputBlobShape.ref.y;
      tensor.shape.z = outputBlobShape.ref.z;
      tensor.shape.w = outputBlobShape.ref.w;
      tensor.shape.dim = outputBlobShape.ref.dim;
      tensor.data = data;

      malloc.free(embedding);
      malloc.free(outputBlobIdx);
      malloc.free(outputBlobShape);

      outputTensor.add(tensor);
    }

    malloc.free(outputBlobCnt);

    return outputTensor;
  }

  List<AiliaDetail> getInputDetails() {
    List<AiliaDetail> details = List<AiliaDetail>.empty(growable: true);
    final Pointer<Uint32> inputBlobCount = malloc<Uint32>();
    inputBlobCount.value = 0;
    int status = ailia.ailiaGetInputBlobCount(ppAilia!.value, inputBlobCount);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaGetInputBlobCount error $status");
    }

    for (int i = 0; i < inputBlobCount.value; i++) {
      Pointer<ailia_dart.AILIAShape> inputBlobShape =
          malloc<ailia_dart.AILIAShape>();
      final Pointer<Uint32> inputBlobIdx = malloc<Uint32>();
      inputBlobIdx.value = 0;
      status = ailia.ailiaGetBlobIndexByInputIndex(
        ppAilia!.value,
        inputBlobIdx,
        i,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobIndexByOutputIndex error $status");
      }
      status = ailia.ailiaGetBlobShape(
        ppAilia!.value,
        inputBlobShape,
        inputBlobIdx.value,
        ailia_dart.AILIA_SHAPE_VERSION,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobShape error $status");
      }
      AiliaShape shape = AiliaShape();
      shape.x = inputBlobShape.ref.x;
      shape.y = inputBlobShape.ref.y;
      shape.z = inputBlobShape.ref.z;
      shape.w = inputBlobShape.ref.w;
      shape.dim = inputBlobShape.ref.dim;

      final Pointer<Uint32> blobNameLength = malloc<Uint32>();
      blobNameLength.value = 0;
      status = ailia.ailiaGetBlobNameLengthByIndex(
          ppAilia!.value, inputBlobIdx.value, blobNameLength);
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetBlobNameLengthByIndex error $status");
      }
      final Pointer<Int8> blobName = malloc<Int8>(blobNameLength.value);
      status = ailia.ailiaFindBlobNameByIndex(
        ppAilia!.value,
        blobName,
        blobNameLength.value,
        inputBlobIdx.value,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaFindBlobNameByIndex error $status");
      }

      AiliaDetail detail = AiliaDetail();
      detail.name = blobName.cast<Utf8>().toDartString();
      detail.shape = shape;

      details.add(detail);

      malloc.free(inputBlobIdx);
      malloc.free(inputBlobShape);
      malloc.free(blobName);
      malloc.free(blobNameLength);
    }

    malloc.free(inputBlobCount);

    return details;
  }

  void close() {
    if (!_available) {
      return;
    }

    Pointer<ailia_dart.AILIANetwork> net = ppAilia!.value;
    ailia.ailiaDestroy(net);
    malloc.free(ppAilia!);

    _available = false;
  }

  static List<AiliaEnvironment> getEnvironmentList() {
    List<AiliaEnvironment> envList =
        List<AiliaEnvironment>.empty(growable: true);
    final ailia =
        ailia_dart.ailiaFFI(_ailiaCommonGetLibrary(_ailiaCommonGetPath()));

    final Pointer<Uint32> count = malloc<Uint32>();
    count.value = 0;
    int status = ailia.ailiaGetEnvironmentCount(count);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaGetEnvironmentCount failed $status");
    }

    for (int envIdx = 0; envIdx < count.value; envIdx++) {
      Pointer<Pointer<ailia_dart.AILIAEnvironment>> ppEnv =
          malloc<Pointer<ailia_dart.AILIAEnvironment>>();
      status = ailia.ailiaGetEnvironment(
        ppEnv,
        envIdx,
        ailia_dart.AILIA_ENVIRONMENT_VERSION,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaGetEnvironment failed $status");
      }
      Pointer<ailia_dart.AILIAEnvironment> pEnv = ppEnv.value;
      malloc.free(ppEnv);
      AiliaEnvironment env = AiliaEnvironment();
      try {
        env.id = pEnv.ref.id;
        env.props = pEnv.ref.props;
        env.name = pEnv.ref.name
            .cast<Utf8>()
            .toDartString(); // This always fails one time in this loop
        envList.add(env);
      } catch (error) {
        print("ailiaGetEnvironment failed $error");
      }
    }
    malloc.free(count);
    return envList;
  }
}

class AiliaDetectorModel {
  Pointer<Pointer<ailia_dart.AILIADetector>>? ppDetector;
  AiliaModel? model;
  bool available = false;

  void close() {
    if (!available) {
      return;
    }

    model!.ailia.ailiaDestroyDetector(ppDetector!.value);
    malloc.free(ppDetector!);

    model!.close();
    available = false;
  }

  void openFile(String onnxPath,
      {int envId = ailia_dart.AILIA_ENVIRONMENT_ID_AUTO,
      int memoryMode = ailia_dart.AILIA_MEMORY_OPTIMAIZE_DEFAULT,
      int networkImageFormat = ailia_dart.AILIA_NETWORK_IMAGE_FORMAT_BGR,
      int networkChannelFormat = ailia_dart.AILIA_NETWORK_IMAGE_CHANNEL_FIRST,
      int networkImageRange =
          ailia_dart.AILIA_NETWORK_IMAGE_RANGE_UNSIGNED_INT8,
      int algorithm = ailia_dart.AILIA_DETECTOR_ALGORITHM_YOLOX,
      int numCategory = 80,
      int flags = ailia_dart.AILIA_DETECTOR_FLAG_NORMAL,
      int inputWidth = 640,
      int inputHeight = 640}) {
    close();
    model = AiliaModel();
    model!.openFile(onnxPath, envId: envId, memoryMode: memoryMode);

    ppDetector = malloc<Pointer<ailia_dart.AILIADetector>>();

    int status = model!.ailia.ailiaCreateDetector(
        ppDetector,
        model!.ppAilia!.value,
        networkImageFormat,
        networkChannelFormat,
        networkImageRange,
        algorithm,
        numCategory,
        flags);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaCreate failed $status");
    }

    status = model!.ailia
        .ailiaDetectorSetInputShape(ppDetector!.value, inputWidth, inputHeight);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaDetectorSetInputShape failed $status");
    }

    available = true;
  }

  List<AiliaDetectorObject> run(Uint8List img, int width, int height,
      {double threshold = 0.4,
      double iou = 0.45,
      int format = ailia_dart.AILIA_IMAGE_FORMAT_RGB}) {
    List pixel = img.buffer.asUint8List().toList();

    if (!available) {
      throw Exception("instance not available");
    }

    int channels = 4;
    if (format == ailia_dart.AILIA_IMAGE_FORMAT_RGB ||
        format == ailia_dart.AILIA_IMAGE_FORMAT_BGR) {
      channels = 3;
    }
    if (pixel.length != width * height * channels) {
      throw Exception("invalid image format");
    }

    Pointer<Uint8> inputData = malloc<Uint8>(pixel.length);
    for (int j = 0; j < pixel.length; j++) {
      inputData[j] = pixel[j];
    }

    int status = model!.ailia.ailiaDetectorCompute(
        ppDetector!.value,
        inputData.cast<Void>(),
        width * channels,
        width,
        height,
        format,
        threshold,
        iou);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaDetectorCompute failed $status");
    }

    malloc.free(inputData);
    final Pointer<Uint32> count = malloc<Uint32>();
    count.value = 0;
    status = model!.ailia.ailiaDetectorGetObjectCount(ppDetector!.value, count);
    if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
      throw Exception("ailiaDetectorGetObjectCount failed $status");
    }

    List<AiliaDetectorObject> objList =
        List<AiliaDetectorObject>.empty(growable: true);

    for (int idx = 0; idx < count.value; idx++) {
      Pointer<ailia_dart.AILIADetectorObject> pObj =
          malloc<ailia_dart.AILIADetectorObject>();
      status = model!.ailia.ailiaDetectorGetObject(
        ppDetector!.value,
        pObj,
        idx,
        ailia_dart.AILIA_DETECTOR_OBJECT_VERSION,
      );
      if (status != ailia_dart.AILIA_STATUS_SUCCESS) {
        throw Exception("ailiaDetectorGetObject failed $status");
      }

      AiliaDetectorObject obj = AiliaDetectorObject();
      obj.x = pObj.ref.x;
      obj.y = pObj.ref.y;
      obj.w = pObj.ref.w;
      obj.h = pObj.ref.h;
      obj.category = pObj.ref.category;
      obj.prob = pObj.ref.prob;

      malloc.free(pObj);
      objList.add(obj);
    }
    malloc.free(count);

    return objList;
  }
}
