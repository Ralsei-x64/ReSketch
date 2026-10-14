// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include "include/cef_app.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_render_process_handler.h"
#include <QStringList>
#include <functional>
#include <map>
#include <string>
#include <vector>

class ReSketchCefApp : public CefApp, public CefBrowserProcessHandler, public CefRenderProcessHandler {
  public:
    explicit ReSketchCefApp(std::vector<std::string> switches = {}, std::function<void(int64_t)> pump = {});
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
    CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return this; }
    void OnBeforeCommandLineProcessing(const CefString &, CefRefPtr<CefCommandLine>) override;
    void OnScheduleMessagePumpWork(int64_t delay) override;
    void OnBrowserCreated(CefRefPtr<CefBrowser>, CefRefPtr<CefDictionaryValue>) override;
    void OnBrowserDestroyed(CefRefPtr<CefBrowser>) override;
    void OnContextCreated(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefV8Context>) override;
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefProcessId,
                                  CefRefPtr<CefProcessMessage>) override;

  private:
    std::vector<std::string> switches;
    std::function<void(int64_t)> pump;
    std::map<int, CefRefPtr<CefListValue>> scripts;
    IMPLEMENT_REFCOUNTING(ReSketchCefApp);
};
namespace ReSketchCef {
void initialize(const QStringList &switches = {});
void shutdown();
void browserCreated(CefRefPtr<CefBrowser> browser);
void browserClosed(int id);
bool initialized();
} // namespace ReSketchCef
