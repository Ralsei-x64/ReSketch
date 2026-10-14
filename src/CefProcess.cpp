// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefApp.h"
// Chromium renews the stack guard after zygote fork. This entry frame must
// not compare the inherited guard when CefExecuteProcess returns in a child.
__attribute__((no_stack_protector)) int main(int argc, char **argv) {
    CefMainArgs args(argc, argv);
    return CefExecuteProcess(args, new ReSketchCefApp, nullptr);
}
