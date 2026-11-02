/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */
#include "total.h"

#include <numeric>
#include <vector>

extern "C" long long adder_total(const long long *values, size_t count)
{
    std::vector<long long> numbers(values, values + count);
    return std::accumulate(numbers.begin(), numbers.end(), 0LL);
}
