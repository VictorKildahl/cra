// Entry point for every Chromium subprocess (renderer, GPU, utility, plugin,
// alerts). Enters the macOS sandbox, then loads the framework from the
// enclosing Cra.app bundle and hands control to CEF.
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_sandbox_mac.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_library_loader.h"

namespace {

// send(string) for Cra's page scripts: the string goes to the browser process as a
// "Cra.page" message. Pages never see this function (it is only an argument to Cra's
// own script) and nothing reaches the page's console.
class SendHandler : public CefV8Handler {
 public:
  bool Execute(const CefString& name, CefRefPtr<CefV8Value> object, const CefV8ValueList& arguments,
               CefRefPtr<CefV8Value>& retval, CefString& exception) override {
    if (arguments.empty() || !arguments[0]->IsString()) return true;
    CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
    CefRefPtr<CefFrame> frame = context ? context->GetFrame() : nullptr;
    if (!frame || !frame->IsValid()) return true;
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("Cra.page");
    message->GetArgumentList()->SetString(0, arguments[0]->GetStringValue());
    frame->SendProcessMessage(PID_BROWSER, message);
    return true;
  }
  IMPLEMENT_REFCOUNTING(SendHandler);
};

// Runs Cra's page scripts ("Cra.run" from CraCEF's RunPageScript) in the frame's page:
// the script is a function expression called with send(). Exceptions stay here, so a
// script that fails leaves nothing in DevTools either. A named script runs once per
// document; later runs call the function it returned.
class RenderHandler : public CefRenderProcessHandler {
 public:
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                CefProcessId source_process, CefRefPtr<CefProcessMessage> message) override {
    if (source_process != PID_BROWSER || message->GetName() != "Cra.run") return false;
    CefRefPtr<CefListValue> args = message->GetArgumentList();
    std::string name = args->GetString(0).ToString();
    CefRefPtr<CefV8Context> context = frame ? frame->GetV8Context() : nullptr;
    if (!context || !context->IsValid() || !context->Enter()) return true;
    if (!name.empty()) {
      for (const Installed& i : installed_) {
        if (i.name != name || !i.context->IsSame(context)) continue;
        if (i.again && i.again->IsFunction()) i.again->ExecuteFunction(nullptr, {});
        context->Exit();
        return true;
      }
    }
    CefRefPtr<CefV8Value> script;
    CefRefPtr<CefV8Exception> error;
    if (context->Eval(args->GetString(1), CefString(), 0, script, error) && script && script->IsFunction()) {
      CefRefPtr<CefV8Value> again =
          script->ExecuteFunction(nullptr, {CefV8Value::CreateFunction("send", new SendHandler())});
      if (!name.empty()) installed_.push_back({context, name, again});
    }
    context->Exit();
    return true;
  }

  void OnContextReleased(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         CefRefPtr<CefV8Context> context) override {
    for (auto i = installed_.begin(); i != installed_.end();) {
      i = i->context->IsSame(context) ? installed_.erase(i) : i + 1;
    }
  }

 private:
  struct Installed {
    CefRefPtr<CefV8Context> context;
    std::string name;
    CefRefPtr<CefV8Value> again;
  };
  std::vector<Installed> installed_;
  IMPLEMENT_REFCOUNTING(RenderHandler);
};

class HelperApp : public CefApp {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return render_handler_; }

 private:
  CefRefPtr<RenderHandler> render_handler_ = new RenderHandler();
  IMPLEMENT_REFCOUNTING(HelperApp);
};

}  // namespace

int main(int argc, char* argv[]) {
  // The seatbelt profile has to be in place before the framework loads.
  // libcef_sandbox.dylib ships inside the framework (Libraries/).
  CefScopedSandboxContext sandbox_context;
  if (!sandbox_context.Initialize(argc, argv)) {
    return 1;
  }
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }
  CefMainArgs main_args(argc, argv);
  CefRefPtr<CefApp> app = new HelperApp();
  return CefExecuteProcess(main_args, app, nullptr);
}
