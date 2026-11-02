/*
 * SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
 * SPDX-License-Identifier: MIT-0
 */
#ifndef ADDER_TOTAL_H
#define ADDER_TOTAL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The sum of count numbers, computed in C++. */
long long adder_total(const long long *values, size_t count);

#ifdef __cplusplus
}
#endif

#endif
