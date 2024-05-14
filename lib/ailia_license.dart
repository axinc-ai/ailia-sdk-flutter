import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ailia.dart' as ailia_dart;

class AiliaLicense {
  static const String licenseServer = 'axip-console.appspot.com';
  static const String licenseApi = '/license/download/product/AILIA';
  static const String licenseFileFormat =
      '--- shalo license file ---\naxell:ailia\n';
  static bool displayLicenseWarning = true;

  static void debugPrint(String message){
    print(message);
  }

  static Future<void> _downloadLicense(String licPath) async {
    final uri = Uri.https(licenseServer, licenseApi);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final licenseFile = response.bodyBytes;
      await File(licPath).writeAsBytes(licenseFile);
    } else {
      throw Exception("License file download failed");
    }
  }

  static Future<String?> _checkLicense(String licPath) async {
    final file = File(licPath);
    if (!await file.exists()) {
      debugPrint("License file $licPath is not found.");
      return null;
    }

    String licenseFileContent = await file.readAsString();
    licenseFileContent = licenseFileContent.replaceAll('\r\n', '\n');
    if (!licenseFileContent.startsWith(licenseFileFormat)) {
      debugPrint("License file $licPath has invalid format.");
      return null;
    }

    final lines = licenseFileContent.split('\n');
    final RegExp exp = RegExp(r'(\d{4})\/(\d{2})\/(\d{2})');
    final match = exp.firstMatch(lines[2]);

    if (match == null) {
      debugPrint("License file $licPath has invalid format.");
      return null;
    }

    final expiryDate = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      23,
      59,
      59,
    );
    if (DateTime.now().isAfter(expiryDate)) {
      debugPrint("License date of $licPath has been expired.");
      return null;
    }

    return lines.length > 3 ? lines[3] : "";
  }

  static void _displayWarning() {
    if (!displayLicenseWarning) return;

    final String defaultLocale = Platform.localeName;
    if (defaultLocale.contains("ja")) {
      debugPrint(
          "ailiaへようこそ。ailia SDKは商用ライブラリです。特定の条件下では、無償使用いただけますが、原則として有償ソフトウェアです。詳細は https://ailia.ai/license/ を参照してください。");
    } else {
      if (defaultLocale.contains("zh")) {
        debugPrint(
            "欢迎来到ailia。ailia SDK是商业库。在特定条件下，可以免费使用，但原则上是付费软件。详情请参阅 https://ailia.ai/license/ 。");
      } else {
        debugPrint(
            "Welcome to ailia! The ailia SDK is a commercial library. Under certain conditions, it can be used free of charge; however, it is principally paid software. For details, please refer to https://ailia.ai/license/ .");
      }
    }

    displayLicenseWarning = false;
  }

  static String _getLicenseFolderPath() {
    Map<String, String> envVars = Platform.environment;
    var home = envVars['HOME'];
    var folderPath = "";
    if (Platform.isMacOS) {
      folderPath = "$home/Library/SHALO/";
      Directory(folderPath).createSync();
    } else if (Platform.isWindows) {
      folderPath = Directory.current.path;
    } else if (Platform.isLinux) {
      folderPath = "$home/.shalo/";
    }
    return folderPath;
  }

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

  static String _pointerCharToString(Pointer<Int8> pointer) {
    var length = 0;
    while (pointer.elementAt(length).value != 0) {
      length++;
    }

    var buffer = Uint8List(length);
    for (var i = 0; i < length; i++) {
      buffer[i] = pointer.elementAt(i).value;
    }

    return utf8.decode(buffer);
  }

  static Future<void> checkAndDownloadLicense() async {
    var ailia = ailia_dart.ailiaFFI(_ailiaCommonGetLibrary(_ailiaCommonGetPath()));
    final Pointer<Int8> versionPointer = ailia.ailiaGetVersion();
    String version = _pointerCharToString(versionPointer);

    if (version.contains("perpetual_license")) {
      return;
    }

    final licFolder = _getLicenseFolderPath();
    final licFile = "$licFolder/AILIA.lic";

    var userData = await _checkLicense(licFile);
    if (userData == null) {
      debugPrint("Downloading license file for ailia SDK.");
      await Directory(licFolder).create(recursive: true);
      await _downloadLicense(licFile);
      userData = await _checkLicense(licFile);
    }

    if (userData == null) {
      debugPrint("Download license file failed.");
      return;
    }

    if (userData.contains("trial version")) {
      _displayWarning();
    }
  }
}
