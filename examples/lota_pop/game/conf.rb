# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT-0
#++

# Lota reads this before it opens the window.
module Lota
  # Names the window, and sizes it where the system lets a window be sized.
  def self.conf(t)
    t.window.title = "Pop"
    t.window.width = 480
    t.window.height = 640
  end
end
