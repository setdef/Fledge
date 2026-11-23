# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# What every page of Lent shares: the layout of the same name, and no
# forgery protection. A browser sends a cookie with a form another site
# posts, which the token stops; Lent's pages are at tokra://localhost/,
# which no other site's page can post a form to, and only Lent's own
# window loads them.
class ApplicationController < ActionController::Base
  skip_forgery_protection
end
