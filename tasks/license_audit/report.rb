# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

class LicenseAudit
  # What the audit found: the components present, which file each
  # component owns, what each compiled file links and has compiled in,
  # every violation, and the bytes of each file the audit read from
  # inside an archive (LicenseAudit#bytes), by its ARCHIVE!ENTRY name.
  class Report < Data.define(:platform, :tree, :components, :owners, :binaries, :links, :embeds, :violations, :archived)
    # The bytes of the file at +path+ in the tree, or of the archive
    # entry it names.
    def bytes(path)
      archived.fetch(path) { File.binread(File.join(tree, path)) }
    end

    def symlink?(path)
      !archived.key?(path) && File.symlink?(File.join(tree, path))
    end

    def owned(component)
      owners.select { |_path, owner| owner.equal?(component) }.keys.sort
    end

    def embedded_in(component)
      embeds.select { |_path, ids| ids.include?(component.id) }.keys.sort
    end

    def present
      components.select { |component| !owned(component).empty? || !embedded_in(component).empty? }
    end
  end
end
