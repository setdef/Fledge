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
      # whose contents are +size+ bytes. When the app's gems need the
      # Visual C++ runtime DLLs +visual_c_runtime+, which the app does not
      # carry, it installs Microsoft's Redistributable from
      # +redistributable+ first, if the computer lacks one of them.
      def initialize(identity:, folder:, to:, files:, folders:, size:, signing: nil, visual_c_runtime: [], redistributable: "")
        @identity = identity
        @folder = folder
        @to = to
        @files = files
        @folders = folders
        @size = size
        @signing = signing
        @visual_c_runtime = visual_c_runtime
        @redistributable = redistributable
      end

      # The installer's NSIS script, with the app's icon at +icon+, or
      # NSIS's own for +nil+, a license page that shows the file at
      # +license+, or none for +nil+, and the bitmap at +sidebar+ down the
      # left side of the finish page, or NSIS's own for +nil+.
      def text(icon:, license: nil, sidebar: nil)
        lines = header(icon, sidebar) + pages(license) + functions + visual_c_section + install_section + uninstall_section
        "#{lines.join("\n")}\n"
      end

      # What runs before anything is installed, for an app built with
      # <tt>windows: { visual_c_runtime: central }</tt>: when the native
      # System32 lacks one of the DLLs its launcher looks for, it downloads
      # Microsoft's Redistributable into the setup program's own temporary
      # folder ($PLUGINSDIR), with URLDownloadToFileW through the System
      # plug-in, runs it, which asks for an administrator itself, and looks
      # again. If one is still missing, the person chooses to abort, to
      # retry, or to install the app without it, whose launcher then names
      # it; a silent install aborts. Nothing for any other app.
      private def visual_c_section
        return [] if @visual_c_runtime.empty?

        installer = "$PLUGINSDIR\\#{nsis(File.basename(@redistributable))}"
        run = -> (mode) { "        ExecWait '\"#{installer}\" /install /#{mode} /norestart' $1" }
        [
          *missing_visual_c_macro,
          "Section VisualCRuntime",
          "  fledge_visual_c_runtime:",
          "  !insertmacro FledgeMissingVisualCRuntime",
          "  ${If} $0 != \"\"",
          "    DetailPrint #{quote("Downloading Microsoft's Visual C++ Redistributable from #{@redistributable}")}",
          "    InitPluginsDir",
          "    Delete \"#{installer}\"",
          "    System::Call 'urlmon::URLDownloadToFileW(p 0, w #{quote(@redistributable)}, w \"#{installer}\", i 0, p 0) i .r1'",
          "    StrCpy $2 0",
          "    ClearErrors",
          "    FileOpen $3 \"#{installer}\" r",
          "    ${IfNot} ${Errors}",
          "      FileSeek $3 0 END $2",
          "      FileClose $3",
          "    ${EndIf}",
          "    ${If} $1 <> 0",
          "      DetailPrint \"The download failed (HRESULT $1)\"",
          "    ${ElseIf} $2 = 0",
          "      DetailPrint \"The download left no installer at #{installer}\"",
          "    ${Else}",
          "      DetailPrint \"Installing Microsoft's Visual C++ Redistributable\"",
          "      ClearErrors",
          "      ${If} ${Silent}",
          run.call("quiet"),
          "      ${Else}",
          run.call("passive"),
          "      ${EndIf}",
          "      ${If} ${Errors}",
          "        DetailPrint \"The Redistributable's installer could not be started\"",
          "      ${Else}",
          "        DetailPrint \"Microsoft's Visual C++ Redistributable exited with $1\"",
          "      ${EndIf}",
          "    ${EndIf}",
          "    !insertmacro FledgeMissingVisualCRuntime",
          "    ${If} $0 != \"\"",
          "      MessageBox MB_ICONEXCLAMATION|MB_ABORTRETRYIGNORE #{redistributable_message} " \
            "/SD IDABORT IDRETRY fledge_visual_c_runtime IDIGNORE fledge_visual_c_runtime_done",
          "      Abort",
          "    ${EndIf}",
          "  ${EndIf}",
          "  fledge_visual_c_runtime_done:",
          "SectionEnd",
          "",
        ]
      end

      # Sets $0 to the first of the Visual C++ runtime's DLLs the native
      # System32 lacks, or "" when it has them all: the files the launcher
      # looks for, where it looks. The setup program is 32-bit, so
      # Windows would show it SysWOW64 for System32; Sysnative is the
      # native folder's name to a 32-bit program (Microsoft's "File System
      # Redirector").
      private def missing_visual_c_macro
        [
          "!macro FledgeMissingVisualCRuntime",
          "  StrCpy $0 \"\"",
          *@visual_c_runtime.flat_map do |name|
            [
              "  ${If} $0 == \"\"",
              "  ${AndIfNot} ${FileExists} \"$WINDIR\\Sysnative\\#{nsis(name)}\"",
              "    StrCpy $0 #{quote(name)}",
              "  ${EndIf}",
            ]
          end,
          "!macroend",
          "",
        ]
      end

      # What the person reads when the Redistributable is still missing,
      # quoted as NSIS reads it, with the missing DLL's name from $0.
      private def redistributable_message
        name = nsis(@identity.name)
        "\"#{name} needs Microsoft's Visual C++ Redistributable, which this computer does not have ($WINDIR\\System32 has no $0) " \
          "and which could not be installed. Install it from #{@redistributable} and choose Retry, or choose Ignore to " \
          "install #{name} without it, which then does not start until the Redistributable is installed.\""
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
      # and then on the installer, failing unless it exits 0. The
      # command goes in the first of NSIS's three quote characters it
      # does not hold, since NSIS has no escape for a quote of the same
      # kind inside a string.
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

      private def header(icon, sidebar)
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
        lines << "!define MUI_WELCOMEFINISHPAGE_BITMAP #{quote(Nsis.host_path(sidebar))}" if sidebar
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
      # (Config::FileAssociation), under
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
        folders = folder_verb
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
        return [] unless opens_folders?

        [
          "  WriteRegStr HKCU #{verb} \"\" #{quote("Open with #{@identity.name}")}",
          "  WriteRegStr HKCU #{classes("Directory\\shell\\#{@identity.identifier}\\command")} \"\" #{open_command}",
        ]
      end

      # What the uninstaller removes of #folder_verb.
      private def folder_verb_removal
        return [] unless opens_folders?

        ["  DeleteRegKey HKCU #{verb}"]
      end

      private def opens_folders?
        @identity.file_associations.any?(&:folders)
      end

      # Each extension the app opens, as Windows, which ignores case, knows
      # it, and the name of the first entry that lists it.
      private def opened_extensions
        pairs = @identity.file_associations.flat_map { |association| association.extensions.map { |extension| [extension.downcase, association.name] } }
        pairs.uniq(&:first).to_h { |extension, name| [extension.to_s, name.to_s] }
      end

      # What the uninstaller removes of #associations: the ProgIDs, their
      # values in each extension's +OpenWithProgids+, each extension's keys
      # when nothing else is left in them, and the folders' verb.
      private def dissociations
        folders = folder_verb_removal
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
      # a reordered list or a renamed entry keeps it;
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
