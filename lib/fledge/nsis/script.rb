# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../version_info"

module Fledge
  class Nsis
    # The NSIS script of one app's installer: its settings and version
    # information, its pages, and its install and uninstall sections,
    # with every name in it quoted as NSIS reads a string.
    class Script # :nodoc:
      # The script that installs the app of +identity+ from +folder+ into
      # the setup program +to+, and uninstalls +files+ and +folders+,
      # whose contents are +size+ bytes.
      def initialize(identity:, folder:, to:, files:, folders:, size:)
        @identity = identity
        @folder = folder
        @to = to
        @files = files
        @folders = folders
        @size = size
      end

      # The installer's NSIS script, with the app's icon at +icon+, or
      # NSIS's own for +nil+.
      def text(icon:)
        lines = header(icon) + pages + functions + install_section + uninstall_section
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
          "SectionEnd",
        ]
      end

      # The app's program, as the installed folder holds it.
      private def program
        "#{@identity.name}.exe"
      end

      private def header(icon)
        numbers = VersionInfo.numbers(@identity.version)
        lines = [
          "Unicode true",
          "ManifestDPIAware true",
          "SetCompressor /SOLID zlib",
          "RequestExecutionLevel user",
          "",
          "!include MUI2.nsh",
          "!include LogicLib.nsh",
          "!include Win\\COM.nsh",
          "!include Win\\Propkey.nsh",
          "",
          "Name #{quote(@identity.name)}",
          "OutFile #{quote(Nsis.host_path(@to))}",
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

      private def pages
        [
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
