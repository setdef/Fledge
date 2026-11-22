/*
 * SPDX-FileCopyrightText: 2026 setdef <kerrick@setdef.com>
 * SPDX-License-Identifier: MIT
 */

/*
 * The documents a macOS app was opened with, as arguments.
 *
 * Finder's double-click on a document, a drop on the app's icon, and
 * open -a APP FILE all start the app through Launch Services, which
 * gives the document not in argv but in an Open Documents Apple event
 * ('odoc'), sent once the app has checked in with it. Windows and Linux
 * give the path in argv, and so does ruby main.rb FILE, so the launcher
 * takes that one event before Ruby starts and gives the program its
 * paths as arguments after any it was given
 * (doc/contributors/design/launcher.md, "Documents opened on macOS").
 *
 * It does so only for a bundle that declares document types
 * (CFBundleDocumentTypes, written from fledge.yml's file_associations)
 * and that launchd started, as Launch Services starts every app: a
 * program started from a terminal, or by the app itself, has no such
 * event to wait for. Carbon's ReceiveNextEvent checks the process in
 * with Launch Services, as AppKit would, and returns the first Apple
 * event without taking it from the queue. Only an Open Documents event
 * is taken: it is handed to AEProcessEvent with a handler installed for
 * that moment and removed before Ruby starts, so the app's GUI library,
 * if it has one, never receives the document it finds in ARGV. Any
 * other first event, such as the Open Application event ('oapp') of a
 * launch with no document, is left where it is. No NSApplication is
 * made and no delegate set, so SDL, AppKit, and the rest install their
 * own as they always do.
 */

#include "launcher.h"

#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* How long to wait for Launch Services' first event, in seconds. */
static const EventTimeout first_event_timeout = 2.0;

struct documents {
    char **paths;
    int count;
};

/* Whether this program is the main executable of a bundle that declares document types. */
static int
declares_documents(void)
{
    CFBundleRef bundle = CFBundleGetMainBundle();
    if (bundle == NULL) return 0;
    CFTypeRef types = CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("CFBundleDocumentTypes"));
    return types != NULL && CFGetTypeID(types) == CFArrayGetTypeID() && CFArrayGetCount((CFArrayRef)types) > 0;
}

/* Appends the file URL url, of length size, to documents as a path. */
static void
add_path(struct documents *documents, const UInt8 *url, CFIndex size)
{
    CFURLRef parsed = CFURLCreateWithBytes(kCFAllocatorDefault, url, size, kCFStringEncodingUTF8, NULL);
    if (parsed == NULL) return;
    char path[PATH_MAX];
    Boolean converted = CFURLGetFileSystemRepresentation(parsed, true, (UInt8 *)path, sizeof path);
    CFRelease(parsed);
    if (!converted) return;
    char **grown = realloc(documents->paths, sizeof *grown * (size_t)(documents->count + 1));
    if (grown == NULL) return;
    documents->paths = grown;
    char *copy = strdup(path);
    if (copy == NULL) return;
    documents->paths[documents->count++] = copy;
}

/* The Open Documents handler: adds each item of the event's direct object, as a file URL, to documents. */
static OSErr
collect(const AppleEvent *event, AppleEvent *reply, SRefCon context)
{
    (void)reply;
    struct documents *documents = (struct documents *)context;
    AEDescList list = {typeNull, NULL};
    long count = 0;

    if (AEGetParamDesc(event, keyDirectObject, typeAEList, &list) != noErr) return errAEDescNotFound;
    if (AECountItems(&list, &count) == noErr) {
        for (long index = 1; index <= count; index++) {
            AEKeyword keyword;
            DescType type;
            Size size = 0;
            if (AESizeOfNthItem(&list, index, &type, &size) != noErr || size <= 0) continue;
            UInt8 *url = malloc((size_t)size);
            if (url == NULL) continue;
            if (AEGetNthPtr(&list, index, typeFileURL, &keyword, &type, url, size, &size) == noErr) {
                add_path(documents, url, size);
            }
            free(url);
        }
    }
    AEDisposeDesc(&list);
    return noErr;
}

/* Whether event, an Apple event in Carbon's queue, is Open Documents. */
static int
is_open_documents(EventRef event)
{
    AEEventClass event_class = 0;
    AEEventID event_id = 0;

    if (GetEventParameter(event, kEventParamAEEventClass, typeType, NULL, sizeof event_class, NULL, &event_class) !=
        noErr)
        return 0;
    if (GetEventParameter(event, kEventParamAEEventID, typeType, NULL, sizeof event_id, NULL, &event_id) != noErr)
        return 0;
    return event_class == kCoreEventClass && event_id == kAEOpenDocuments;
}

/* Takes the launch's Open Documents event, if it is the first Apple event, into documents. */
static void
take_open_documents(struct documents *documents)
{
    EventTypeSpec apple_event = {kEventClassAppleEvent, kEventAppleEvent};
    EventRef event = NULL;

    if (ReceiveNextEvent(1, &apple_event, first_event_timeout, false, &event) != noErr || event == NULL) return;
    if (!is_open_documents(event)) return;

    AEEventHandlerUPP handler = NewAEEventHandlerUPP(collect);
    if (AEInstallEventHandler(kCoreEventClass, kAEOpenDocuments, handler, (SRefCon)documents, false) == noErr) {
        RetainEvent(event);
        RemoveEventFromQueue(GetMainEventQueue(), event);
        AEProcessEvent(event);
        ReleaseEvent(event);
        AERemoveEventHandler(kCoreEventClass, kAEOpenDocuments, handler, false);
    }
    DisposeAEEventHandlerUPP(handler);
}

int
fledge_launch_documents(char ***paths)
{
    struct documents documents = {NULL, 0};

    *paths = NULL;
    if (getppid() != 1 || !declares_documents()) return 0;
    take_open_documents(&documents);
    *paths = documents.paths;
    return documents.count;
}
