# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#
# What an app that shrinks its code with R8 keeps of the runtime: the
# classes and members Ruby reaches through JNI by name, which R8 sees
# no call of (doc/contributors/design/phone-widgets.md).
-keep class org.setdef.fledge.FledgeRuby { public *; native <methods>; }
-keep class org.setdef.fledge.RubyProxy { *; }
