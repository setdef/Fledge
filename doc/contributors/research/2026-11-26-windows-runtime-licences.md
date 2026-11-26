<!--
SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

> Findings of 2026-11-26 on what Microsoft's texts say about redistributing two runtimes that a Windows app can need: the Windows App Runtime (the Windows App SDK's runtime) and the Visual C++ runtime. Requested: written by an agent and not reviewed line by line. They quote texts and mark every inference; they recommend nothing and decide nothing.

# Redistributing the Windows App Runtime and the Visual C++ runtime: what Microsoft's texts say

An app that draws WinUI 3 needs the Windows App Runtime, and a DLL built with Visual Studio needs the Visual C++ runtime (`doc/contributors/design/gems.md`, "The Visual C++ runtime"). A computer that runs the app may have neither. Whether Fledge may carry a runtime in an app, download it for the person who runs the app, or only name it depends on what Microsoft's licenses and guides allow. This note records those texts, so that a later session starts from them and not from memory.

## How this was read

Every page and license below was read on 2026-11-26, from copies saved that day. A quotation is word for word from a saved copy. The license texts use curly quotation marks and apostrophes; they are written straight here. A sentence that starts with "Inference:" is the note's reading, and no text says it. The two downloaded files (the installer and the zip) were hashed and measured; nothing else of their contents is described.

## Verdict

- **Two license texts go with the Windows App Runtime, and no text read says which one covers the standalone installer or the MSIX packages.** The installer's help text lists `https://aka.ms/windowsappsdk-license`. The NuGet packages `Microsoft.WindowsAppSDK` and `Microsoft.WindowsAppSDK.Runtime` 2.7.0 carry `license.txt`, "MICROSOFT SOFTWARE LICENSE TERMS" with a "DISTRIBUTABLE CODE" section.
- **Microsoft's deployment guide tells the developer of a framework-dependent unpackaged app to deploy the runtime** "either by running the runtime installer or by installing the MSIX packages directly", and calls the Visual C++ Redistributable "a requirement".
- **The Visual C++ runtime's redistribution is "limited to licensed Visual Studio users"** and runs under the terms of the Visual Studio edition they hold: object code on a Distributable List, with a duty to add "significant primary functionality", to bind distributors and end users to protective terms, and, in the 2026 license, to indemnify Microsoft. The license of the standalone Redistributable lists "share, publish, rent, lease, or otherwise distribute the software or any of its code" among the things the licensee may not do.
- **The pages read give no checksum for any of these downloads.** The SHA-256 of the 2.7.0 installer and zip, computed on 2026-11-26, is in section 3.

## 1. Which license governs the Windows App Runtime

### 1.1 The installer's help

The x64 installer, `windowsappruntimeinstall-x64.exe` of Windows App SDK 2.7.0, holds a help text. Its closing lines are:

```
Documentation URI: https://aka.ms/windowsappsdkinstall
Privacy Statement:   https://aka.ms/windowsappsdk-privacy
License Statement:   https://aka.ms/windowsappsdk-license
```

A fetch of `https://aka.ms/windowsappsdk-license` on 2026-11-26 ended at the `LICENSE` file of `https://github.com/microsoft/windowsappsdk`. The saved copy of that file is the MIT License ("Copyright (c) Microsoft Corporation."), which says, among other things: "Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software". The saved files do not record the redirect, only the file it led to.

### 1.2 The NuGet packages' license

`Microsoft.WindowsAppSDK` 2.7.0 and `Microsoft.WindowsAppSDK.Runtime` 2.7.0 each hold a `license.txt`; the two are byte-identical. Each package's `.nuspec` says `<license type="file">license.txt</license>` and `<requireLicenseAcceptance>true</requireLicenseAcceptance>`, and `<projectUrl>` is `https://github.com/microsoft/windowsappsdk`. The text is headed "MICROSOFT SOFTWARE LICENSE TERMS" and "MICROSOFT WINDOWS APP SDK". It does not contain the words "installer" or "MSIX".

Section 1(a), "General": "you may install and use any number of copies of the software to develop and test your applications, solely for use on Windows."

Section 3, "DISTRIBUTABLE CODE": "The software may contain code you are permitted to distribute (i.e. make available for third parties) in applications you develop, as described in this Section."

Section 3(a), "Distribution Rights", item i: "Any files that are binplaced with your application by the WindowsAppSDK NuGet package are, by definition, permitted to be redistributed. This applies to both framework package dependent and self-contained deployments." Item iii: "Third Party Distribution. You may permit distributors of your applications to copy and distribute any of this distributable code you elect to distribute with your applications."

Section 3(b), "Distribution Requirements": "For any code you distribute, you must: i. add significant primary functionality to it in your applications; ii. require distributors and external end users to agree to terms that protect it and Microsoft at least as much as this agreement; and iii. indemnify, defend, and hold harmless Microsoft from any claims, including attorneys' fees, related to the distribution or use of your applications, except to the extent that any claim is based solely on the unmodified distributable code."

Section 3(c), "Distribution Restrictions": "You may not: i. use Microsoft's trademarks or trade dress in your application in any way that suggests your application comes from or is endorsed by Microsoft; or ii. modify or distribute the source code of any distributable code so that any part of it becomes subject to any license that requires that the distributable code, any other part of the software, or any of Microsoft's other intellectual property be disclosed or distributed in source code form, or that others have the right to modify it."

Section 4, "SCOPE OF LICENSE": item c, "remove, minimize, block, or modify any notices of Microsoft or its suppliers in the software"; item e, "share, publish, distribute, or lease the software (except for any distributable code, subject to the terms above), provide the software as a stand-alone offering for others to use, or transfer the software or this agreement to any third party."

Section 1(c), "Microsoft Platforms": "The software may include components from Microsoft Windows. These components are governed by separate agreements and their own product support policies, as described in the license terms found in the installation directory for that component or in the "Licenses" folder accompanying the software."

### 1.3 What the two texts leave open

- Inference: the MIT text and the NuGet text give different rights to a copy of the same version. The MIT License grants the right to "distribute" and "sublicense" with no further duty than keeping the notice. The NuGet text grants distribution only of "distributable code", with the section 3(b) duties.
- No text read says that either license covers the standalone installer or the zip. The installer's help text lists the link to the MIT License; `license.txt` is the license of the NuGet packages that a developer builds an app against.
- Section 3(a)(i) defines distributable files as those "binplaced with your application by the WindowsAppSDK NuGet package". Inference: the installer and the MSIX packages are not files that package places with an app, so section 3(a)(i) does not name them; the text neither includes nor excludes them.
- The 2.7.0 files carry a `NOTICE.txt` that begins "This software incorporates material from third parties." It lists the third parties' licenses; this note does not reproduce it.

## 2. Microsoft's deployment guide

"Windows App SDK deployment guide for framework-dependent unpackaged apps", `https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps` (the page's "Last updated on" is 2026-11-20), says:

- "You're responsible for deploying the required Windows App SDK runtime packages with your unpackaged app, either by running the runtime installer or by installing the MSIX packages directly."
- "The Visual C++ Redistributable is a requirement. For more info, see Microsoft Visual C++ Redistributable latest supported downloads."
- Option 1, the installer: "The silent installer distributes all Windows App SDK MSIX packages. A separate installer is available for each of the X64,X86 and Arm64 architectures." And: "You can run the installer with no user interaction and suppress all text output with the --quiet option: WindowsAppRuntimeInstall.exe --quiet".
- Chaining: "If you have a custom setup program for your app, you can chain the Windows App SDK setup process in your app's setup process." And: "The Windows App SDK installer silently unpacks the Windows App MSIX bundle and calls the PackageManager.AddPackageAsync method to complete the installation. This is very similar to other runtime installers you may have used, like .NET, Visual C++, or DirectX."
- Option 2, the packages: "As an alternative to using the Windows App SDK installer for deployment to end users, you can manually deploy the MSIX packages through your app's program or MSI. This option can be best for developers who want more control."
- Return codes: `0x0` is "Package installation or provisioning was completed successfully."; `0x80073d06` is "One or more packages failed to install."; `0x80070005` is "System-wide install or provisioning was not possible because the app is not running elevated or the user doing the installation doesn't have admin privileges."
- Administrator rights: "If the app is running elevated and the user doing the installation has admin privileges, then the installer will register the MSIX packages system-wide by calling the ProvisionPackageForAllUsersAsync. If system-wide registration is not successful, the installation will be performed for the current user doing the installation only."
- Installed already: "MSIX packages are installed to a system-wide location with only one copy on disk. If an app attempts installation of the Windows App SDK when all the MSIX package dependencies are already installed on the machine, then the installation is not performed."
- Which packages: "When deploying the Windows App SDK, always attempt to install all the MSIX packages (framework, main, singleton, DDLM) to ensure that all dependencies are installed and you avoid disruption to the end-user experience."
- After installing, an unpackaged app has more to do: "Installing the runtime packages doesn't, by itself, add the Framework package to your app's process package graph." The app uses the Bootstrapper API for that.

"Windows App SDK deployment architecture and overview", `https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deployment-architecture` (last updated 2026-11-20), under "Additional requirements": "For packaged apps, the VCLibs framework package dependency is a requirement." and "For unpackaged apps, the Visual C++ Redistributable is a requirement." It also says: "Self-contained deployment is an alternative for all three packaging options. Self-contained apps carry the Framework binaries app-locally and don't need a Framework MSIX dependency or Bootstrapper initialization for those binaries."

Neither page says anything about licenses. Neither says whether a developer may put the installer or the MSIX packages into an archive of the app, only that the developer is "responsible for deploying" them.

## 3. Where the files come from

"Latest Windows App SDK downloads", `https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads` (last updated 2026-11-18), lists for each stable version an "Installer (x64)", "Installer (x86)", "Installer (arm64)", and "Redistributable (ZIP)", and for 2.7.0 gives the date "11/17/2026". It describes the two kinds:

- Installer: "The standalone .exe installer, WindowsAppRuntimeInstall.exe, is available as a separate download beginning with Windows App SDK 1.0.1. It installs the Windows App SDK Runtime which includes the Framework, Main, Singleton and DDLM packages."
- Redistributable: "The Windows App Runtime Redistributable (Microsoft.WindowsAppRuntime.Redist) is a zip file that includes the installer and MSIX packages for all architectures (x64, x86, and ARM64)."

The links are `aka.ms` redirects that carry the version, for example:

- `https://aka.ms/windowsappsdk/2.7/2.7.0/windowsappruntimeinstall-x64.exe`
- `https://aka.ms/windowsappsdk/2.7/2.7.0/Microsoft.WindowsAppRuntime.Redist.2.7.zip`

The pages read give no SHA-256 or other checksum for any of these files. The values below were computed on 2026-11-26 from copies downloaded from the two links above:

| File | Size in bytes | SHA-256 |
|---|---|---|
| `windowsappruntimeinstall-x64.exe`, 2.7.0 | 125,486,904 | `ed1ac8aa9497473389a288017c7fc352c382ba8df6c08f36ddb5815bff283b2a` |
| `Microsoft.WindowsAppRuntime.Redist.2.7.zip`, 2.7.0 | 547,333,668 | `144d1cf0489e576f841505baed22a866634bd8b8d7c395f7e1a31d42a8cc651a` |

The x64 installer inside the zip has the same SHA-256 as the standalone one. Inference: a version's `aka.ms` link stays pointed at that version's file, since the version is in the link; no text read says so.

## 4. The Visual C++ runtime

### 4.1 Microsoft Learn

"Redistribute Visual C++ files", `https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170` (last updated 2026-04-15), under "Redistributable files and licensing":

- "Distribution of the Visual C++ Runtime Redistributable package, merge modules, and individual binaries is limited to licensed Visual Studio users and is subject to Microsoft Software License Terms."
- "When you deploy an application, you must also deploy the files that are required to support it. If Microsoft provides any of these files, check whether you're permitted to redistribute them."
- "To view the "REDIST list" that's referenced in the "Distributable Code" section of the Visual Studio 2022 Microsoft Software License Terms, see Distributable code files for Microsoft Visual Studio 2022."

Under "Install the redistributable packages": "The Visual C++ Redistributable packages install and register all Visual C++ libraries. If you use one, run it as a prerequisite on the target system before you install your application. We recommend that you use these packages for your deployments because they enable automatic updating of the Visual C++ libraries." And: "If you aren't running from an elevated command prompt, you'll need to respond to a User Account Control prompt to allow the installer to run with administrative privileges." The page lists `/quiet` ("doesn't display a user interface or require any user interaction") and `/norestart`.

Under "Install individual redistributable files": "It's also possible to directly install the Redistributable DLLs in the application local folder. [...] For servicing reasons, we don't recommend that you use this installation location."

"Determine which DLLs to redistribute", `https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute?view=msvc-170`:

- "You can't redistribute all of the files that are included in Visual Studio. You're only permitted to redistribute the files that are specified in Redist.txt or the online "REDIST list.""
- "You also can't redistribute debug versions of your applications, or the debug versions of DLLs or libraries supplied by Microsoft."
- "We only support using a Redistributable package that's the same as or newer than your toolset version."
- "You may use these libraries for local deployment, by installing them in the same directory as your application. We don't recommend local deployment because it makes you responsible for delivering updates to your deployed applications. Central deployment by using the Redistributable packages is preferred."

"Microsoft Visual C++ Redistributable latest supported downloads", `https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170`: "Redistribution is permitted only for licensed Visual Studio users, as described in the Visual Studio license terms. For details on redistributing Visual C++ files, see Redistribute Visual C++ files." And: "If your app is built by using those libraries, a Microsoft Visual C++ Redistributable package at least as recent as the build tools used to build your app must be installed on the target system along with the app."

"Distributable Code for Visual Studio 2022", `https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution`, the "Distributable List":

- "If you have a validly licensed copy of such software, you may copy and distribute with your program the unmodified form of the files listed below, subject to the License Terms for the software." ("Such software" is Visual Studio Enterprise 2022, Professional 2022, and Community 2022.)
- Under "Visual C++ Runtime Files": "Subject to the License Terms for the software, you may copy and distribute with your program any of the files within the following folder and its subfolders except as noted below. You may not modify these files." The folder is `[VisualStudioFolder]\VC\redist`.
- "The same Visual C++ Runtime Redistributable package is available from Latest supported Visual C++ Redistributable downloads and Download Visual Studio Tools. Distribution of the Visual C++ Runtime Redistributable package, merge modules, and individual binaries obtained from those pages is limited to licensed Visual Studio users and is subject to its license terms."
- "You may not distribute the contents of the following folders", the two `debug_nonredist` folders.

### 4.2 The Visual Studio 2022 and 2026 Community licenses

Both licenses are "MICROSOFT SOFTWARE LICENSE TERMS", for "MICROSOFT VISUAL STUDIO COMMUNITY 2022" and "MICROSOFT VISUAL STUDIO COMMUNITY 2026" (the latter "Last Updated: October 1, 2025."). They are linked from `https://visualstudio.microsoft.com/license-terms/`; the saved copies are the pages `vs2022-ga-community` and `vs2026-ga-community` under that address. The 2022 text calls the section "this Section 4".

Installation and use rights, both versions: "Individual License. If you are an individual working on your own applications, either to sell or for any other purpose, you may use the software to develop and test those applications." The organizational and enterprise rules differ; this note does not summarize them.

"DISTRIBUTABLE CODE" in 2022: "The software contains code that you may distribute in applications you develop as described in this Section. For purposes of this Section 4, the term "distribution" also means deployment of your applications for third parties to access over the Internet." The 2026 text has the same two sentences, the second reading "this Section" where the 2022 text reads "this Section 4".

- Right to Use and Distribute: "The code and text files listed below are "Distributable Code"." (2026: "listed in (i) and (ii) below".) "Distributable List. You may copy and distribute the object code form of code listed on the Distributable List located at https://aka.ms/vs/17/redistribution." (2026: `https://aka.ms/vs/18/redistribution`.)
- "Third Party Distribution. You may permit distributors of your applications to copy and distribute the Distributable Code as part of those applications."
- Distribution Requirements, 2022: "For any Distributable Code you distribute, you must: add significant primary functionality to it in your applications; and require distributors and external end users to agree to terms that protect the Distributable Code at least as much as this agreement."
- Distribution Requirements, 2026: the same two requirements, and a third: "indemnify, defend, and hold harmless Microsoft from any claims, including attorneys' fees, related to the distribution or use of your applications, except to the extent that any claim is based solely on the Distributable Code."
- Distribution Restrictions, 2022: "distribute components or runtimes that are marked "Preview", "Pre-release" or "Beta""; use Microsoft's trademarks in an app's name or so as to suggest Microsoft endorses it; and "modify or distribute the source code of any Distributable Code so that any part of it becomes subject to an Excluded License." 2026 adds "distribute Unreleased Components" and "distribute software developed with Insiders Channel Software or that depends on Unreleased Components".

Build devices, 2022: "Build Devices and Visual Studio Build Tools. You may copy and install files from the software or from Visual Studio Build Tools onto your build devices, including physical devices and virtual machines or containers on those machines, whether on-premises or remote machines that are owned by you, hosted on Microsoft Azure for you, or dedicated solely to your use (collectively, "Build Devices"). You and others in your organization may us these files on your Build Devices solely to compile, build, and verify applications developed by using the software, or run quality or performance tests of those applications as part of the build process." (The 2022 text reads "may us"; the 2026 text reads "may use" and adds, besides computers owned by you and hosted on Azure for you, ones "under the day-to-day management and control of an Authorized Outsourcer (as defined below) and dedicated solely to your use".)

### 4.3 The standalone Redistributable's license

`https://visualstudio.microsoft.com/license-terms/vs2026-ga-visualcpp-v14-redist-runtime/`, "License Terms | Microsoft Visual C++ V14 Redistributable and Runtime 2026". The license is "MICROSOFT VISUAL C++ V14 REDISTRIBUTABLE and RUNTIME", "Last Updated: October 1, 2025", EULA ID `Cpp_v14_ENU.1033`.

- "INSTALLATION AND USE RIGHTS. You may install and use any number of copies of the software."
- "SCOPE OF LICENSE. [...] You may not [...] share, publish, rent, lease, or otherwise distribute the software or any of its code; or provide the software as a stand-alone offering or combined with any of your applications for others to use, or transfer the software or these license terms to any third party."
- "BY USING THE SOFTWARE, YOU ACCEPT THESE TERMS."

It has no "Distributable Code" section.

### 4.4 What the texts leave open

- Inference: the Distributable List, under a Visual Studio edition's license, permits distributing the runtime's files, and the standalone Redistributable's license forbids distributing the software or any of its code; the two texts differ about the same files. The Learn page of the Distributable List ties them: the package "obtained from those pages is limited to licensed Visual Studio users and is subject to its license terms". No text read says which of the two licenses governs a `vc_redist` file that a licensed Visual Studio user has obtained from the download page, or one copied out of the Visual Studio folder `VC\redist`.
- The pages say "licensed Visual Studio users". The Community license's use rights (individual; an organization's open source, education, and up to five users otherwise; no enterprise use but for named exceptions) say who may develop and test with the software. No text read says whether a person who builds with a different compiler, or with Visual Studio Build Tools alone, is a "licensed Visual Studio user".
- "Distribution" is defined as also meaning "deployment of your applications for third parties to access over the Internet". No text read says whether a download of an app by a person from a developer's site, or an app made by a service from a developer's inputs, is a distribution by the developer or by the service, or both.
- The Build Devices clause lets a licensee install files from the software on a build device "solely to compile, build, and verify applications". Inference: it says nothing of copying files from the software into the app that the build makes, which is a distribution under section 4, so section 4's duties would apply to that copy and the Build Devices clause would not. No text read says so either way.
- The 2022 Community license has no indemnity duty and the 2026 one has. Inference: a developer whose copy of Visual Studio is the 2022 edition and one whose copy is the 2026 edition promise different things to Microsoft for the same files.

## Sources

Every row was read on 2026-11-26.

| Source | Title | Where |
|---|---|---|
| `https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps` | Windows App SDK deployment guide for framework-dependent unpackaged apps | section 2 |
| `https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deployment-architecture` | Windows App SDK deployment architecture and overview | section 2 |
| `https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads` | Latest Windows App SDK downloads | section 3 |
| `https://github.com/microsoft/windowsappsdk`, `LICENSE` | MIT License | section 1.1 |
| `Microsoft.WindowsAppSDK` and `Microsoft.WindowsAppSDK.Runtime` 2.7.0 (`.nupkg`), `license.txt` and `.nuspec` | MICROSOFT SOFTWARE LICENSE TERMS, MICROSOFT WINDOWS APP SDK | section 1.2 |
| `windowsappruntimeinstall-x64.exe` 2.7.0, its help text | none | section 1.1 |
| `https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170` | Redistribute Visual C++ Files | section 4.1 |
| `https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute?view=msvc-170` | Determine which DLLs to redistribute | section 4.1 |
| `https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170` | Latest Supported Visual C++ Redistributable Downloads | section 4.1 |
| `https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution` | Visual Studio 2022 Redistribution (heading "Distributable Code for Visual Studio 2022") | section 4.1 |
| `https://visualstudio.microsoft.com/license-terms/` | Visual Studio Community 2022 and 2026 license terms | section 4.2 |
| `https://visualstudio.microsoft.com/license-terms/vs2026-ga-visualcpp-v14-redist-runtime/` | License Terms, Microsoft Visual C++ V14 Redistributable and Runtime 2026 | section 4.3 |
