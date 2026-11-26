# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#
# What an app that shrinks its code with R8 keeps of the runtime: the
# native methods the library registers by name, which R8 sees no call
# of, and the public methods a host calls.
-keep class org.setdef.fledge.FledgeRuby { public *; native <methods>; }
