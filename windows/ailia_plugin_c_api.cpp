#include "include/ailia/ailia_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "ailia_plugin.h"

void AiliaPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  ailia::AiliaPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
