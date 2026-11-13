// The engine test build's app (docs/chromium-engine.md, step 1): a bare executable that hands the process
// to Chrome's framework through Cra's entry point. Links the framework at launch (see Sources/CraHelper/main.cc).
extern "C" int CraEngineMain(int argc, const char** argv);

int main(int argc, const char** argv) {
  return CraEngineMain(argc, argv);
}
