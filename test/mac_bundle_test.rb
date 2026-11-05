# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "json"
require "open3"

# Fledge::MacBundle's Info.plist keys for the files and folders an app
# opens (ADR 032, section 3), and, on a Mac, what plutil reads of them.
class MacBundleTest < Minitest::Test
  ASSOCIATION = Fledge::Config::FileAssociation

  def identity(file_associations)
    Fledge::Identity.new(name: "Hello Window", kind: "windowed", identifier: "com.example.HelloWindow", version: "1.2.3", publisher: nil,
      copyright: nil, icon: nil, description: nil, long_description: nil, homepage: nil, file_associations:)
  end

  def info(file_associations)
    Fledge::MacBundle.new(identity(file_associations), folder: "dist").info
  end

  # Each entry is a document type ranked Alternate: offered, and never
  # the default unless the person makes it one. A folder is
  # public.folder; extensions and MIME types are as electron-builder
  # writes them, and content types are LSItemContentTypes.
  def test_declares_each_document_type_ranked_alternate
    types = info([
      ASSOCIATION.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true),
      ASSOCIATION.new(name: "Project archive", role: "editor", extensions: ["zip"], mime_types: ["application/zip"], content_types: [],
        folders: false),
      ASSOCIATION.new(name: "Picture", role: "viewer", extensions: [], mime_types: [], content_types: ["public.png"], folders: false),
    ]).fetch("CFBundleDocumentTypes")

    folder = { "CFBundleTypeName" => "Project folder", "CFBundleTypeRole" => "Viewer", "LSHandlerRank" => "Alternate" }
    archive = { "CFBundleTypeName" => "Project archive", "CFBundleTypeRole" => "Editor", "LSHandlerRank" => "Alternate" }
    picture = { "CFBundleTypeName" => "Picture", "CFBundleTypeRole" => "Viewer", "LSHandlerRank" => "Alternate" }
    assert_equal [
      folder.merge("LSItemContentTypes" => ["public.folder"]),
      archive.merge("CFBundleTypeExtensions" => ["zip"], "CFBundleTypeMIMETypes" => ["application/zip"]),
      picture.merge("LSItemContentTypes" => ["public.png"]),
    ], types
    refute info([]).key?("CFBundleDocumentTypes"), "an app that opens nothing declares nothing"
  end

  # plutil, which writes the bundle's Info.plist, reads them back.
  def test_plutil_reads_them_back
    skip "plutil is macOS's" unless RUBY_PLATFORM.include?("darwin")

    Dir.mktmpdir do |dir|
      json = File.join(dir, "Info.plist.json")
      plist = File.join(dir, "Info.plist")
      folder = ASSOCIATION.new(name: "Project folder", role: "viewer", extensions: [], mime_types: [], content_types: [], folders: true)
      File.write(json, JSON.generate(info([folder])))
      _, status = Open3.capture2e("plutil", "-convert", "xml1", "-o", plist, json)
      assert_predicate status, :success?
      out, = Open3.capture2("plutil", "-extract", "CFBundleDocumentTypes.0.LSItemContentTypes.0", "raw", "-o", "-", plist)
      assert_equal "public.folder\n", out
      out, = Open3.capture2("plutil", "-extract", "CFBundleDocumentTypes.0.LSHandlerRank", "raw", "-o", "-", plist)
      assert_equal "Alternate\n", out
    end
  end
end
