// SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
// SPDX-License-Identifier: MIT

// A library for Ruby's ffi, with C++ inside and C outside, as libsass is:
// it calls nothing of Ruby's and defines no Init function.
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>

extern "C" char *echoer_shout(const char *text) {
  std::string loud(text);
  std::transform(loud.begin(), loud.end(), loud.begin(), [](unsigned char c) { return std::toupper(c); });
  char *copy = static_cast<char *>(std::malloc(loud.size() + 1));
  std::memcpy(copy, loud.c_str(), loud.size() + 1);
  return copy;
}

extern "C" void echoer_free(char *text) { std::free(text); }
