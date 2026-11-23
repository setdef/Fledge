/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT-0
 */
#ifndef TALLY_H
#define TALLY_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The sum of count numbers, computed in C++, into total. Returns 1, or 0
 * when the sum is too big for a long long.
 */
int tally_sum(const long long *values, size_t count, long long *total);

/* Which CMake built the library, for which system, and for which processor. */
const char *tally_built_for(void);

#ifdef __cplusplus
}
#endif

#endif
