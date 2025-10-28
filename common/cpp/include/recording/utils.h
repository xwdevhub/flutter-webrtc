#ifndef FLUTTER_WEBRTC_RECODING_UTILS_HXX
#define FLUTTER_WEBRTC_RECODING_UTILS_HXX

#if defined(WIN32) || defined(_WINDOWS)
#include <windows.h>

namespace flutter_webrtc_plugin {

// 将 UTF-8 字符串转换为 UTF-16 宽字符串
inline std::wstring utf8_to_wstring(const std::string& utf8_str) {
  if (utf8_str.empty()) {
    return std::wstring();
  }
  int size_needed = MultiByteToWideChar(CP_UTF8, 0, &utf8_str[0], (int)utf8_str.size(), NULL, 0);
  std::wstring wstrTo(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, &utf8_str[0], (int)utf8_str.size(), &wstrTo[0], size_needed);
  return wstrTo;
}

// 将 UTF-16 宽字符串转换为 UTF-8 字符串
inline std::string wstring_to_utf8(const std::wstring& wstr) {
  if (wstr.empty()) {
    return std::string();
  }
  int size_needed =
      WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
  std::string strTo(size_needed, 0);
  WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &strTo[0], size_needed, NULL, NULL);
  return strTo;
}

}  // namespace flutter_webrtc_plugin

#endif

#endif