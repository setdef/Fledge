# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # Judges each component a tree ships by Fledge's license policy
  # (Fledge::LicensePolicy, ADR 004): a notice-only license anywhere, a
  # file-level one only for unmodified files, and an LGPL one either as
  # its own shared library with a source pin, or linked into another
  # component that is not Fledge's own and whose source Fledge publishes
  # beside the LGPL library's (the AppImage runtime and its libfuse, ADR
  # 010), so whoever receives an app can rebuild that component with
  # another copy of the library (LGPL-2.1, section 6(a)). An LGPL library
  # is never allowed linked into the program an app's developer ships as
  # their own, the launcher. A license that asks only that a binary say
  # where its source is (CPL-1.0, NSIS's LZMA module's) is allowed when
  # Fledge publishes the component's source.
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
      when :source_offer
        return if published?(component)

        @violate.call("policy", where, "#{component.id} is #{component.license}, which asks for its source, and needs a source pin in runtime/sources.yml")
      when :shared_library
        check_shared_library(component, report, where)
      else
        @violate.call("policy", where, "#{component.id} is #{component.license}, which the policy does not allow in an app")
      end
    end

    private def check_shared_library(component, report, where)
      return check_linked(component, report, where) if component.kind != "shared_library" && !report.embedded_in(component).empty?
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

    # An LGPL library linked into other files: each must be owned by a
    # component whose own source Fledge publishes and which is not
    # Fledge's, and the library's source must be published too.
    private def check_linked(component, report, where)
      @violate.call("policy", where, "#{component.id} is #{component.license} and needs a source pin in runtime/sources.yml") unless published?(component)
      report.embedded_in(component).each do |path|
        owner = report.owners[path]
        next if owner && !owner.first_party && published?(owner)

        @violate.call("policy", path, "#{component.id} is #{component.license}, linked into a file whose own source Fledge does not publish")
      end
    end

    # Whether Fledge publishes +component+'s source beside the runtime.
    def published?(component)
      @sources.key?(component.source.to_s)
    end
  end
end
