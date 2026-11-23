/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "total.h"

#include <vector>

extern "C" int adder_total(const long long *values, size_t count, long long *total)
{
    std::vector<long long> numbers(values, values + count);
    long long sum = 0;
    for (long long number : numbers) {
        if (__builtin_add_overflow(sum, number, &sum)) return 0;
    }
    *total = sum;
    return 1;
}
