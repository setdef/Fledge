# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
# SPDX-License-Identifier: MIT
#++

require "digest"
require_relative "../windows_resources"

module Fledge
  class Nsis
    # The NSIS script of one app's installer: its settings and version
    # information, its pages, and its install and uninstall sections,
    # with every name in it quoted as NSIS reads a string.
    class Script # :nodoc:
      # Where one person's file types and verbs are, under HKCU.
      CLASSES = 'Software\Classes'

      # The longest ProgID, by Microsoft's ProgID key page, and how many
      # hexadecimal digits of a hash end one.
      PROG_ID_MAX = 39
      PROG_ID_HASH = 10

      # Tells Explorer that file associations changed: SHChangeNotify with
      # SHCNE_ASSOCCHANGED and SHCNF_FLUSH.
      CHANGE_NOTIFY = "  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0x1000, p 0, p 0)'"

      # The characters NSIS quotes a string with, in the order the
      # signing command is tried in them.
      QUOTES = ["'", "`", '"'].freeze

      # The script that installs the app of +identity+ from +folder+ into
      # the setup program +to+, and uninstalls +files+ and +folders+,
      # whose contents are +size+ bytes.
      def initialize(identity:, folder:, to:, files:, folders:, size:, signing: nil)
        @identity = identity
        @folder = folder
        @to = to
        @files = files
        @folders = folders
        @size = size
        @signing = signing
      end

      # The installer's NSIS script, with the app's icon at +icon+, or
      # NSIS's own for +nil+, and a license page that shows the file at
      # +license+, or none for +nil+.
      def text(icon:, license: nil)
        lines = header(icon) + pages(license) + functions + install_section + uninstall_section
        "#{lines.join("\n")}\n"
      end

      # What runs before the installer's pages, and the function its last
      # page's checkbox calls.
      private def functions
        [
          "Function .onInit",
          "  ReadRegStr $0 HKCU #{key} \"InstallLocation\"",
          "  StrCmp $0 \"\" +2",
          "  StrCpy $INSTDIR $0",
          "FunctionEnd",
          "",
          "Function CreateDesktopShortcut",
          "  CreateShortcut \"$DESKTOP\\#{nsis(@identity.name)}.lnk\" \"$INSTDIR\\#{nsis(program)}\"",
          "  !insertmacro FledgeSetAppUserModelId \"$DESKTOP\\#{nsis(@identity.name)}.lnk\"",
          "FunctionEnd",
          "",
        ]
      end

      # The install: the old version's uninstaller first, then the files,
      # the uninstaller, the Start menu shortcut, and the registry.
      private def install_section
        [
          "Section Install",
          "  IfFileExists \"$INSTDIR\\#{UNINSTALLER}\" 0 +3",
          "  ExecWait '\"$INSTDIR\\#{UNINSTALLER}\" /S _?=$INSTDIR'",
          "  Delete \"$INSTDIR\\#{UNINSTALLER}\"",
          "  SetOutPath $INSTDIR",
          "  File /r #{quote(Nsis.host_path(File.join(@folder, '*')))}",
          "  WriteUninstaller \"$INSTDIR\\#{UNINSTALLER}\"",
          "  CreateShortcut \"$SMPROGRAMS\\#{nsis(@identity.name)}.lnk\" \"$INSTDIR\\#{nsis(program)}\"",
          "  !insertmacro FledgeSetAppUserModelId \"$SMPROGRAMS\\#{nsis(@identity.name)}.lnk\"",
          *registry,
          *associations,
          "SectionEnd",
          "",
        ]
      end

      # The uninstall: the shortcuts, exactly the files and folders the
      # install wrote, deepest first, the folder if it is then empty, and
      # the registry key.
      private def uninstall_section
        [
          "Section Uninstall",
          "  Delete \"$SMPROGRAMS\\#{nsis(@identity.name)}.lnk\"",
          "  Delete \"$DESKTOP\\#{nsis(@identity.name)}.lnk\"",
          *@files.map { |path| "  Delete #{installed(path)}" },
          "  Delete \"$INSTDIR\\#{UNINSTALLER}\"",
          *@folders.sort_by { |path| [-path.count("/"), path] }.map { |path| "  RMDir #{installed(path)}" },
          "  RMDir $INSTDIR",
          "  DeleteRegKey HKCU #{key}",
          *dissociations,
          "SectionEnd",
        ]
      end

      # The app's program, as the installed folder holds it.
      # NSIS 3.08's !uninstfinalize and !finalize: makensis runs the
      # signing command on the uninstaller it writes into the installer,
      # and then on the installer, failing unless it exits 0 (ADR 016). The
      # command goes in the first of NSIS's three quote characters it
      # does not hold, since NSIS has no escape for a quote of the same
      # kind inside a string (ADR 033).
      private def finalize
        signing = @signing
        return [] unless signing

        quote = QUOTES.find { |mark| !signing.include?(mark) }
        raise Error, "the signing command holds ', \", and ` all, so makensis cannot quote it; put it in a .cmd file and give that" unless quote

        ["!uninstfinalize #{quote}#{signing}#{quote} = 0", "!finalize #{quote}#{signing}#{quote} = 0"]
      end

      private def program
        "#{@identity.name}.exe"
      end

      private def header(icon)
        numbers = WindowsResources.numbers(@identity.version)
        lines = [
          "Unicode true",
          "ManifestDPIAware true",
          "SetCompressor /SOLID lzma",
          "RequestExecutionLevel user",
          "",
          "!include MUI2.nsh",
          "!include LogicLib.nsh",
          "!include Win\\COM.nsh",
          "!include Win\\Propkey.nsh",
          "",
          "Name #{quote(@identity.name)}",
          "OutFile #{quote(Nsis.host_path(@to))}",
          *finalize,
          "InstallDir \"$LOCALAPPDATA\\Programs\\#{nsis(@identity.name)}\"",
          "BrandingText #{quote(@identity.copyright || @identity.name)}",
          "",
          "VIProductVersion #{numbers.join('.')}",
          "VIFileVersion #{numbers.join('.')}",
          "VIAddVersionKey ProductName #{quote(@identity.name)}",
          "VIAddVersionKey FileDescription #{quote("#{@identity.name} Setup")}",
          "VIAddVersionKey FileVersion #{quote(@identity.version)}",
          "VIAddVersionKey ProductVersion #{quote(@identity.version)}",
        ]
        lines << "VIAddVersionKey CompanyName #{quote(@identity.publisher.to_s)}" if @identity.publisher
        lines << "VIAddVersionKey LegalCopyright #{quote(@identity.copyright.to_s)}" if @identity.copyright
        lines.push("!define MUI_ICON #{quote(Nsis.host_path(icon))}", "!define MUI_UNICON #{quote(Nsis.host_path(icon))}") if icon
        lines + ["", *aumid_macro, ""]
      end

      # Sets a shortcut's System.AppUserModel.ID to the identifier, through
      # IShellLink, IPersistFile, and IPropertyStore, as Tauri's utils.nsh
      # does, but with the VT_LPWSTR the property is (Propkey.nsh).
      private def aumid_macro
        [
          "!macro FledgeSetAppUserModelId shortcut",
          "  !insertmacro ComHlpr_CreateInProcInstance ${CLSID_ShellLink} ${IID_IShellLink} r0 \"\"",
          "  ${If} $0 P<> 0",
          "    ${IUnknown::QueryInterface} $0 '(\"${IID_IPersistFile}\",.r1)'",
          "    ${If} $1 P<> 0",
          "      ${IPersistFile::Load} $1 '(\"${shortcut}\",${STGM_READWRITE})'",
          "      ${IUnknown::QueryInterface} $0 '(\"${IID_IPropertyStore}\",.r2)'",
          "      ${If} $2 P<> 0",
          "        System::Call '*${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_ID})p.r3'",
          "        System::Call '*(&w#{@identity.identifier.to_s.length + 1} #{quote(@identity.identifier.to_s)})p.r4'",
          "        System::Call '*${SYSSTRUCT_PROPVARIANT}(${VT_LPWSTR},,&i4 $4)p.r5'",
          "        ${IPropertyStore::SetValue} $2 '($3,$5)'",
          "        ${IPropertyStore::Commit} $2 \"\"",
          "        ${IPersistFile::Save} $1 '(\"${shortcut}\",1)'",
          "        System::Free $3",
          "        System::Free $4",
          "        System::Free $5",
          "        ${IUnknown::Release} $2 \"\"",
          "      ${EndIf}",
          "      ${IUnknown::Release} $1 \"\"",
          "    ${EndIf}",
          "    ${IUnknown::Release} $0 \"\"",
          "  ${EndIf}",
          "!macroend",
        ]
      end

      # The pages: Modern UI's license page first, when there is a
      # license, which a person accepts before anything else, as Tauri's
      # installer.nsi shows it; then the folder, the files, and the last
      # page. A silent install (/S) shows none of them.
      private def pages(license)
        first = license ? ["!insertmacro MUI_PAGE_LICENSE #{quote(Nsis.host_path(license))}"] : [] # : Array[String]
        [
          *first,
          "!insertmacro MUI_PAGE_DIRECTORY",
          "!insertmacro MUI_PAGE_INSTFILES",
          "!define MUI_FINISHPAGE_RUN \"$INSTDIR\\#{nsis(program)}\"",
          "!define MUI_FINISHPAGE_SHOWREADME",
          "!define MUI_FINISHPAGE_SHOWREADME_TEXT \"Create a desktop shortcut\"",
          "!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED",
          "!define MUI_FINISHPAGE_SHOWREADME_FUNCTION CreateDesktopShortcut",
          "!insertmacro MUI_PAGE_FINISH",
          "!insertmacro MUI_UNPAGE_CONFIRM",
          "!insertmacro MUI_UNPAGE_INSTFILES",
          "!insertmacro MUI_LANGUAGE English",
          "",
        ]
      end

      private def registry
        values = {
          "DisplayName" => @identity.name,
          "DisplayVersion" => @identity.version,
          "Publisher" => @identity.publisher,
          "URLInfoAbout" => @identity.homepage,
          "HelpLink" => @identity.homepage,
        }.compact.map { |name, value| "  WriteRegStr HKCU #{key} #{quote(name)} #{quote(value.to_s)}" }
        values + [
          "  WriteRegStr HKCU #{key} \"DisplayIcon\" \"$INSTDIR\\#{nsis(program)}\"",
          "  WriteRegStr HKCU #{key} \"InstallLocation\" \"$INSTDIR\"",
          "  WriteRegStr HKCU #{key} \"UninstallString\" '\"$INSTDIR\\#{UNINSTALLER}\"'",
          "  WriteRegStr HKCU #{key} \"QuietUninstallString\" '\"$INSTDIR\\#{UNINSTALLER}\" /S'",
          "  WriteRegDWORD HKCU #{key} \"NoModify\" 1",
          "  WriteRegDWORD HKCU #{key} \"NoRepair\" 1",
          "  WriteRegDWORD HKCU #{key} \"EstimatedSize\" #{(@size + 1023) / 1024}",
        ]
      end

      # The registry entries of the files and folders the app opens
      # (Config::FileAssociation; ADR 032, section 3), under
      # <tt>HKCU\Software\Classes</tt>, which needs no administrator. For
      # files, a ProgID of the app's for each extension (#prog_id), named
      # for the documents, with the app's icon and the command
      # that opens one, and listed in each extension's +OpenWithProgids+,
      # which adds the app to Explorer's "Open with" and leaves the
      # extension's default alone; electron-builder's FileAssociation.nsh
      # lists its own there, and sets the default too. For folders, a verb
      # every folder gets, "Open with NAME". Then SHChangeNotify, as
      # Tauri's and electron-builder's installers call it, so Explorer
      # reads them at once.
      private def associations
        folders = @identity.file_associations.any?(&:folders) ? folder_verb : []
        lines = folders + opened_extensions.flat_map do |extension, name|
          progid = prog_id(extension)
          [
            "  WriteRegStr HKCU #{classes(progid)} \"\" #{quote(name)}",
            "  WriteRegStr HKCU #{classes("#{progid}\\DefaultIcon")} \"\" '\"$INSTDIR\\#{nsis(program)}\",0'",
            "  WriteRegStr HKCU #{classes("#{progid}\\shell\\open\\command")} \"\" #{open_command}",
            "  WriteRegNone HKCU #{classes(".#{extension}\\OpenWithProgids")} #{quote(progid)}",
          ]
        end
        lines.empty? ? lines : [*lines, CHANGE_NOTIFY]
      end

      # The verb every folder gets, "Open with NAME".
      private def folder_verb
        [
          "  WriteRegStr HKCU #{verb} \"\" #{quote("Open with #{@identity.name}")}",
          "  WriteRegStr HKCU #{classes("Directory\\shell\\#{@identity.identifier}\\command")} \"\" #{open_command}",
        ]
      end

      # Each extension the app opens, as Windows, which ignores case, knows
      # it, and the name of the first entry that lists it.
      private def opened_extensions
        pairs = @identity.file_associations.flat_map { |association| association.extensions.map { |extension| [extension.downcase, association.name] } }
        pairs.uniq(&:first)
      end

      # What the uninstaller removes of #associations: the ProgIDs, their
      # values in each extension's +OpenWithProgids+, each extension's keys
      # when nothing else is left in them, and the folders' verb.
      private def dissociations
        folders = @identity.file_associations.any?(&:folders) ? ["  DeleteRegKey HKCU #{verb}"] : []
        lines = folders + opened_extensions.flat_map do |extension, _name|
          progid = prog_id(extension)
          [
            "  DeleteRegKey HKCU #{classes(progid)}",
            "  DeleteRegValue HKCU #{classes(".#{extension}\\OpenWithProgids")} #{quote(progid)}",
            "  DeleteRegKey /ifempty HKCU #{classes(".#{extension}\\OpenWithProgids")}",
            "  DeleteRegKey /ifempty HKCU #{classes(".#{extension}")}",
          ]
        end
        lines.empty? ? lines : [*lines, CHANGE_NOTIFY]
      end

      # The key of the verb every folder gets.
      private def verb
        classes("Directory\\shell\\#{@identity.identifier}")
      end

      # The command that opens a file or folder: the program, with the
      # path as its one argument.
      private def open_command
        "'\"$INSTDIR\\#{nsis(program)}\" \"%1\"'"
      end

      # The ProgID of +extension+: the identifier, without what Microsoft's
      # ProgID rules forbid (more than PROG_ID_MAX characters, punctuation
      # but periods, a digit first), then a hash of the identifier and the
      # extension. It depends on nothing that can move or be reworded, so
      # a reordered list or a renamed entry keeps it (ADR 032, section 3);
      # the hash keeps two identifiers the rest would make alike apart.
      private def prog_id(extension)
        hash = Digest::SHA256.hexdigest("#{@identity.identifier}\n#{extension}")[0, PROG_ID_HASH].to_s
        readable = @identity.identifier.to_s.delete("^A-Za-z0-9.").squeeze(".").sub(/\A[0-9.]+/, "")
        readable = readable[0, PROG_ID_MAX - PROG_ID_HASH - 1].to_s.delete_suffix(".")
        "#{readable.empty? ? 'App' : readable}.#{hash}"
      end

      # +path+ under CLASSES, quoted.
      private def classes(path)
        quote("#{CLASSES}\\#{path}")
      end

      private def key
        quote("#{UNINSTALL_KEY}\\#{@identity.identifier}")
      end

      private def installed(path)
        "\"$INSTDIR\\#{nsis(path.tr('/', '\\'))}\""
      end

      # +text+ inside an NSIS string in double quotes: a dollar sign
      # doubled, so NSIS reads no variable in it, and a double quote as
      # <tt>$\"</tt> (NSIS's "Script File Format").
      private def nsis(text)
        text.gsub("$", "$$").gsub('"', '$\\"')
      end

      private def quote(text)
        "\"#{nsis(text)}\""
      end
    end
  end
end
