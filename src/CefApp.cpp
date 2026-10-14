// SPDX-FileCopyrightText: 2026 Ralsei-x64
// SPDX-License-Identifier: GPL-3.0-only
#include "CefApp.h"
#include "include/cef_parser.h"
#include "include/cef_process_message.h"
#include "include/cef_v8.h"
#include <unistd.h>

namespace {
class NativeBridge final : public CefV8Handler {
  public:
    explicit NativeBridge(CefRefPtr<CefFrame> frame) : frame(frame) {}
    bool Execute(const CefString &, CefRefPtr<CefV8Value>, const CefV8ValueList &args,
                 CefRefPtr<CefV8Value> &result, CefString &) override {
        if (args.size() != 2 || !args[0]->IsString() || !args[1]->IsString())
            return false;
        auto message = CefProcessMessage::Create("resketch.bridge");
        message->GetArgumentList()->SetString(0, args[0]->GetStringValue());
        message->GetArgumentList()->SetString(1, args[1]->GetStringValue());
        message->GetArgumentList()->SetString(2, frame->GetURL());
        frame->SendProcessMessage(PID_BROWSER, message);
        result = CefV8Value::CreateBool(true);
        return true;
    }

  private:
    CefRefPtr<CefFrame> frame;
    IMPLEMENT_REFCOUNTING(NativeBridge);
};
const char *notificationBridge = R"JS((()=>{
    if (!/(^|\.)figma\.com$/.test(location.hostname)) return;
    let next=0;const prefix=Date.now().toString(36)+'-'+Math.random().toString(36).slice(2)+'-';const notifications=window.__resketchNotifications=new Map();
    class NativeNotification extends EventTarget {
        constructor(title, options={}) {
            super();this.id=prefix+String(++next);this.title=String(title);this.body=String(options.body||'');
            notifications.set(this.id,this);
            __resketchNative('notification',JSON.stringify({id:this.id,title:this.title,body:this.body}));
        }
        close(){__resketchNative('close-notification',this.id);notifications.delete(this.id);this.dispatchEvent(new Event('close'));}
        static get permission(){return 'granted';}
        static requestPermission(callback){callback?.('granted');return Promise.resolve('granted');}
    }
    window.Notification=NativeNotification;
    if(window.ServiceWorkerRegistration) ServiceWorkerRegistration.prototype.showNotification=function(title,options){new NativeNotification(title,options);return Promise.resolve();};
})())JS";
} // namespace
ReSketchCefApp::ReSketchCefApp(std::vector<std::string> flags, std::function<void(int64_t)> schedule)
    : switches(std::move(flags)), pump(std::move(schedule)) {}
void ReSketchCefApp::OnBeforeCommandLineProcessing(const CefString &type, CefRefPtr<CefCommandLine> line) {
    if (!type.empty())
        return;
    // CEF's accelerated Linux OSR exports EGL DMA-BUFs through its X11 backend.
    line->AppendSwitchWithValue("ozone-platform", "x11");
    line->AppendSwitchWithValue("use-gl", "angle");
    line->AppendSwitchWithValue("use-angle", "gl-egl");
    line->AppendSwitchWithValue("gtk-version", "3");
    line->AppendSwitch("disable-setuid-sandbox");
    line->AppendSwitchWithValue("remote-debugging-address", "127.0.0.1");
    line->AppendSwitch("enable-smooth-scrolling");
    // Figma opens authentication and file popups asynchronously. The app's
    // navigation policy decides which destinations may become windows/tabs.
    line->AppendSwitch("disable-popup-blocking");
    for (const auto &flag : switches) {
        if (!flag.starts_with("--"))
            continue;
        const auto split = flag.find('=');
        if (split == std::string::npos)
            line->AppendSwitch(flag.substr(2));
        else
            line->AppendSwitchWithValue(flag.substr(2, split - 2), flag.substr(split + 1));
    }
}
void ReSketchCefApp::OnScheduleMessagePumpWork(int64_t delay) {
    if (pump)
        pump(delay);
}
void ReSketchCefApp::OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> info) {
    if (info && info->HasKey("scripts"))
        scripts[browser->GetIdentifier()] = info->GetList("scripts")->Copy();
}
void ReSketchCefApp::OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) {
    scripts.erase(browser->GetIdentifier());
}
void ReSketchCefApp::OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                      CefRefPtr<CefV8Context> context) {
    auto message = CefProcessMessage::Create("resketch.renderer");
    message->GetArgumentList()->SetInt(0, getpid());
    if (frame->IsMain())
        frame->SendProcessMessage(PID_BROWSER, message);
    context->GetGlobal()->SetValue("__resketchNative",
                                   CefV8Value::CreateFunction("__resketchNative", new NativeBridge(frame)),
                                   V8_PROPERTY_ATTRIBUTE_READONLY);
    frame->ExecuteJavaScript(notificationBridge, frame->GetURL(), 0);
    const auto found = scripts.find(browser->GetIdentifier());
    if (found == scripts.end())
        return;
    for (size_t i = 0; i < found->second->GetSize(); ++i) {
        const auto script = found->second->GetDictionary(i);
        if (!frame->IsMain() && !script->GetBool("runsOnSubFrames"))
            continue;
        const std::string source = script->GetString("sourceCode");
        if (source.empty())
            continue;
        if (script->GetInt("injectionPoint") == 0)
            frame->ExecuteJavaScript(source, frame->GetURL(), 0);
        else {
            auto value = CefValue::Create();
            value->SetString(source);
            const std::string json = CefWriteJSON(value, JSON_WRITER_DEFAULT);
            frame->ExecuteJavaScript("(()=>{const apply=()=>{(0,eval)(" + json +
                                         ")};if(document.readyState==='loading')document.addEventListener('"
                                         "DOMContentLoaded',apply,{once:true});else apply()})()",
                                     frame->GetURL(), 0);
        }
    }
}
bool ReSketchCefApp::OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>,
                                              CefProcessId, CefRefPtr<CefProcessMessage> message) {
    if (message->GetName() != "resketch.scripts")
        return false;
    scripts[browser->GetIdentifier()] = message->GetArgumentList()->GetList(0)->Copy();
    return true;
}
