# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-FileComment: Adapted from tasks/license_audit/spdx.rb on Fledge's
#   spike/permissive branch (58edf27d27912d062ccfa5c4960533a220c9eb24).
require "digest"
require "time"

class LicenseAudit
  # An SPDX 2.3 software bill of materials for a runtime, as a Hash ready
  # for JSON (https://spdx.github.io/spdx-spec/v2.3/).
  #
  # The runtime is one package, which contains a package per component
  # and every file, each with its SHA-1 (which SPDX 2.3 requires) and
  # SHA-256. Each component package CONTAINS the files it owns, and the
  # links the audit read become relationships between files and
  # packages: a file STATIC_LINKs each component compiled into it, and
  # DYNAMIC_LINKs each file in the runtime it loads.
  class Spdx
    def initialize(report, version:, created: Time.at(Integer(ENV.fetch("SOURCE_DATE_EPOCH", Time.now.to_i.to_s))).utc)
      @report = report
      @version = version
      @created = created
    end

    def to_h
      name = "fledge-runtime-#{@version}-#{@report.platform}"
      present = @report.present
      {
        "spdxVersion" => "SPDX-2.3",
        "dataLicense" => "CC0-1.0",
        "SPDXID" => "SPDXRef-DOCUMENT",
        "name" => name,
        "documentNamespace" => "https://github.com/setdef/Fledge/spdx/#{name}-#{digest}",
        "creationInfo" => { "created" => @created.iso8601, "creators" => ["Tool: fledge-license-audit-#{@version}"] },
        "packages" => [runtime_package(name), *present.map { |component| package(component) }],
        "files" => @report.owners.keys.sort.map { |path| file(path) },
        "hasExtractedLicensingInfos" => extracted(present),
        "relationships" => relationships(present),
      }
    end

    private def runtime_package(name)
      {
        "SPDXID" => "SPDXRef-Package-runtime",
        "name" => name,
        "versionInfo" => @version,
        "supplier" => "Organization: setdef",
        "downloadLocation" => "https://github.com/setdef/Fledge/releases/tag/v#{@version}",
        "filesAnalyzed" => false,
        "licenseConcluded" => "NOASSERTION",
        "licenseDeclared" => "NOASSERTION",
        "copyrightText" => "NOASSERTION",
        "primaryPackagePurpose" => "APPLICATION",
      }
    end

    # A component that owns files lists them (filesAnalyzed), with the
    # verification code SPDX 2.3 section 7.9 defines over their SHA-1s; one
    # that is only compiled into others' files has none of its own.
    private def package(component)
      owned = @report.owned(component)
      package = {
        "SPDXID" => package_id(component),
        "name" => component.name,
        "versionInfo" => component.version,
        "supplier" => component.supplier || "NOASSERTION",
        "downloadLocation" => component.download,
        "filesAnalyzed" => !owned.empty?,
        "licenseConcluded" => component.license,
        "licenseDeclared" => component.license,
        "copyrightText" => "NOASSERTION",
        "comment" => "Ships as: #{component.ships}",
      }
      return package if owned.empty?

      package.merge("licenseInfoFromFiles" => ["NOASSERTION"],
        "packageVerificationCode" => { "packageVerificationCodeValue" => Digest::SHA1.hexdigest(owned.map { |path| sha1(path) }.sort.join) })
    end

    private def file(path)
      {
        "SPDXID" => file_id(path),
        "fileName" => "./#{path}",
        "checksums" => [
          { "algorithm" => "SHA1", "checksumValue" => sha1(path) },
          { "algorithm" => "SHA256", "checksumValue" => Digest::SHA256.hexdigest(bytes(path)) },
        ],
        "licenseConcluded" => "NOASSERTION",
        "copyrightText" => "NOASSERTION",
      }
    end

    private def extracted(present)
      present.flat_map { |component| component.license.scan(/LicenseRef-[A-Za-z0-9.-]+/) }.uniq.sort.map do |id|
        {
          "licenseId" => id,
          "name" => id.delete_prefix("LicenseRef-"),
          "extractedText" => "See notices/ in the runtime, which holds this license's text.",
        }
      end
    end

    private def relationships(present)
      describes = [{ "spdxElementId" => "SPDXRef-DOCUMENT", "relationshipType" => "DESCRIBES", "relatedSpdxElement" => "SPDXRef-Package-runtime" }]
      contains = present.map { |component| relationship("SPDXRef-Package-runtime", "CONTAINS", package_id(component)) }
      owns = @report.owners.sort.map { |path, owner| relationship(package_id(owner), "CONTAINS", file_id(path)) }
      static = @report.embeds.sort.flat_map do |path, ids|
        ids.uniq.filter_map do |id|
          component = present.find { |candidate| candidate.id == id }
          relationship(file_id(path), "STATIC_LINK", package_id(component)) if component && @report.owners.key?(path)
        end
      end
      dynamic = @report.links.sort.flat_map do |path, libraries|
        libraries.values.grep(String).uniq.map { |library| relationship(file_id(path), "DYNAMIC_LINK", file_id(library)) }
      end
      describes + contains + owns + static + dynamic
    end

    private def relationship(from, type, to)
      { "spdxElementId" => from, "relationshipType" => type, "relatedSpdxElement" => to }
    end

    private def bytes(path)
      @report.symlink?(path) ? File.readlink(File.join(@report.tree, path)) : @report.bytes(path)
    end

    private def sha1(path)
      (@sha1 ||= {})[path] ||= Digest::SHA1.hexdigest(bytes(path))
    end

    private def package_id(component)
      "SPDXRef-Package-#{component.id.gsub(/[^A-Za-z0-9.-]/, '-')}"
    end

    private def file_id(path)
      "SPDXRef-File-#{Digest::SHA256.hexdigest(path)[0, 16]}"
    end

    private def digest
      Digest::SHA256.hexdigest(@report.owners.keys.sort.join("\n"))[0, 16]
    end
  end
end
