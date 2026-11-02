# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0

# What the gem's submodule, github.com/octocat/Hello-World at the commit
# this repository records, says.
module FledgeSubmoduleGem
  README = File.read(File.join(__dir__, "..", "vendor", "hello", "README")).strip
end
