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

    # The kind of program this recipe compiles, for RuntimeBuilder::Hardening
    # (:glibc, :musl, :darwin, or :windows), or nil where it compiles
    # none.
    def hardening_kind
      nil
    end

    # The programs this recipe compiled in +stage+: those Hardening reads.
    def programs(_stage)
      []
    end

    # Raises, naming what each compiled program lacks, when one lacks a
    # protection Hardening asks for (+stage+ is the runtime's folder).
    def verify_hardening(stage)
      kind = hardening_kind or return
      Hardening.new(kind:, readers:).check(programs(stage))
    end

    # The tools the license audit reads the runtime's compiled files with
    # (LicenseAudit.readers): the building computer's own, or LLVM's in
    # FLEDGE_LLVM.
    def readers
      LicenseAudit.readers
    end
  end
end
