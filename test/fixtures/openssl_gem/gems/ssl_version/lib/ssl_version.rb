# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# fledge build compiles this extension against the runtime's own Ruby,
# linked to the OpenSSL the runtime holds for compiling gems.
require "ssl_version/ssl_version"
