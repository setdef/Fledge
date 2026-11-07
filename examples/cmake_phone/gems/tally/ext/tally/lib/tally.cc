/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "tally.h"

#include <string>
#include <vector>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(__APPLE__) && TARGET_OS_SIMULATOR
#define TALLY_VARIANT " Simulator"
#else
#define TALLY_VARIANT ""
#endif

#if defined(__aarch64__) || defined(__arm64__)
#define TALLY_PROCESSOR "arm64"
#elif defined(__x86_64__)
#define TALLY_PROCESSOR "x86_64"
#else
#define TALLY_PROCESSOR "another processor"
#endif

extern "C" int tally_sum(const long long *values, size_t count, long long *total)
{
    std::vector<long long> numbers(values, values + count);
    long long sum = 0;
    for (long long number : numbers) {
        if (__builtin_add_overflow(sum, number, &sum)) return 0;
    }
    *total = sum;
    return 1;
}

/* TALLY_CMAKE_VERSION and TALLY_SYSTEM are what CMake configured
 * (CMakeLists.txt); the variant and the processor are what the compiler
 * aimed at. */
extern "C" const char *tally_built_for(void)
{
    static const std::string text = std::string("CMake ") + TALLY_CMAKE_VERSION + " built for " + TALLY_SYSTEM +
        TALLY_VARIANT + " on " + TALLY_PROCESSOR;
    return text.c_str();
}
