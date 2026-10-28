# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # Judges each component a tree ships by Fledge's license policy
  # (Fledge::LicensePolicy, ADR 004): a notice-only license anywhere, a
  # file-level one only for unmodified files, and an LGPL one only as its
  # own shared library with a source pin.
  class Policy
    # A policy that reads source pins from +sources+ (runtime/sources.yml)
    # and reports each violation to +violate+, with its rule, path, and
    # message.
    def initialize(sources, violate)
      @sources = sources
      @violate = violate
    end

    # Reports each way +component+, which +report+ found in the tree,
    # breaks the policy.
    def check(component, report)
      category = LicenseAudit.category(component.license, first_party: component.first_party)
      where = (report.owned(component) + report.embedded_in(component)).first.to_s
      case category
      when :notice_only, :first_party then nil
      when :file_level
        return if component.kind == "files"

        @violate.call("policy", where, "#{component.id} is #{component.license}, allowed only for unmodified files, but ships as #{component.kind}")
      when :shared_library
        check_shared_library(component, report, where)
      else
        @violate.call("policy", where, "#{component.id} is #{component.license}, which the policy does not allow in an app")
      end
    end

    private def check_shared_library(component, report, where)
      unless component.kind == "shared_library"
        return @violate.call("policy", where, "#{component.id} is #{component.license}, allowed only as a separate shared library, but ships as #{component.kind}")
      end

      @violate.call("policy", where, "#{component.id} is #{component.license} and needs a source pin in runtime/sources.yml") unless @sources.key?(component.source.to_s)
      report.owned(component).each do |path|
        format = report.binaries[path]&.format
        @violate.call("policy", path, "#{component.id} is #{component.license}, so this file must be a shared library, not #{format.inspect}") unless %i[elf pe macho].include?(format)
      end
      return if report.embedded_in(component).all? { |path| report.owners[path].equal?(component) }

      @violate.call("policy", where, "#{component.id} is #{component.license} and is compiled into a file it does not own")
    end
  end
end
