# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "fileutils"

class RuntimeBuilder
  # What every recipe shares: the builder, the folder it works in, and
  # where the launcher's sources are.
  class Recipe
    LAUNCHER = File.join(ROOT, "runtime", "launcher")

    def initialize(builder:, build_dir:)
      @builder = builder
      @build_dir = build_dir
    end

    # The platforms whose computers can build this recipe's runtime.
    def hosts
      [@builder.platform.name]
    end

    # The tools the license audit reads the runtime's compiled files with
    # (LicenseAudit.readers): the building computer's own, or LLVM's in
    # FLEDGE_LLVM.
    def readers
      LicenseAudit.readers
    end

    # The Ruby tree the runtime was made from, once #build has unpacked
    # it, for the build-only companion (RuntimeBuilder::DevCompanion.copy).
    attr_reader :tree
  end
end
