/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#ifndef ADDER_TOTAL_H
#define ADDER_TOTAL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The sum of count numbers, computed in C++, into total. Returns 1, or 0
 * when the sum is too big for a long long.
 */
int adder_total(const long long *values, size_t count, long long *total);

#ifdef __cplusplus
}
#endif

#endif
