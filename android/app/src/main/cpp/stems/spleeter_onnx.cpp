// Spleeter 4-stem nets on ONNX Runtime — the only file that touches ORT.
//
// The fp16 graphs (Best-Practice/spleeter-4stems-onnx) take magnitudes and
// return magnitudes: input "x" and output "y", both float32
// [2, num_splits, 512, 1024]. ORT runs fp16 kernels where the CPU has them and
// otherwise inserts casts to fp32, so the same files work on every device.

#include "separator.h"

#if __has_include(<onnxruntime/onnxruntime_cxx_api.h>)
#include <onnxruntime/onnxruntime_cxx_api.h>  // iOS: onnxruntime-c pod (framework)
#else
#include <onnxruntime_cxx_api.h>              // Android AAR headers / desktop tests
#endif

#include <array>
#include <memory>
#include <vector>

namespace hype {
namespace stems {
namespace {

Ort::Env& ortEnv() {
    // One environment per process: ORT's global state must outlive sessions.
    static Ort::Env* env = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, "hype-stems");
    return *env;
}

const char* kNetFiles[kNetCount] = {"vocals.onnx", "drums.onnx", "bass.onnx", "other.onnx"};

class SpleeterOnnx final : public Separator {
public:
    explicit SpleeterOnnx(int threads) : threads_(threads < 1 ? 1 : threads) {}

    bool load(const std::string& dir, std::string* error) override {
        unload();
        try {
            Ort::SessionOptions so;
            so.SetIntraOpNumThreads(threads_);
            so.SetInterOpNumThreads(1);
            so.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
            // Memory, measured with the four 4-stem nets on an M-series Mac:
            //   defaults (ALL + per-session arenas)  224 MB loaded, 881 MB after runs
            //   EXTENDED, no arena, no mem pattern   124 MB loaded, 341 MB after runs
            // at the same speed. ALL's layout transforms keep a second, re-laid-out
            // copy of every weight; four sessions each holding an arena at its
            // peak is the rest.
            so.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_EXTENDED);
            so.DisableCpuMemArena();
            so.DisableMemPattern();
            // Busy-waiting worker threads burn battery between splits.
            so.AddConfigEntry("session.intra_op.allow_spinning", "0");
            std::array<std::unique_ptr<Ort::Session>, kNetCount> sessions;
            for (int i = 0; i < kNetCount; ++i) {
                const std::string path = dir + "/" + kNetFiles[i];
                sessions[i] = std::make_unique<Ort::Session>(ortEnv(), path.c_str(), so);
            }
            sessions_ = std::move(sessions);
            loaded_ = true;
            return true;
        } catch (const Ort::Exception& e) {
            if (error) *error = e.what();
        } catch (const std::exception& e) {
            if (error) *error = e.what();
        }
        unload();
        return false;
    }

    bool isLoaded() const override { return loaded_; }

    void unload() override {
        for (auto& s : sessions_) s.reset();
        loaded_ = false;
    }

    bool run(int net, const float* mag, float* out, std::string* error) override {
        if (!loaded_ || net < 0 || net >= kNetCount || !sessions_[net]) {
            if (error) *error = "model not loaded";
            return false;
        }
        try {
            static const int64_t kShape[4] = {2, 1, kSplitFrames, kNetBins};
            const size_t count = size_t(2) * kSplitFrames * kNetBins;
            Ort::MemoryInfo mi = Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeCPU);
            Ort::Value in = Ort::Value::CreateTensor<float>(
                mi, const_cast<float*>(mag), count, kShape, 4);
            Ort::Value o = Ort::Value::CreateTensor<float>(mi, out, count, kShape, 4);
            const char* inNames[] = {"x"};
            const char* outNames[] = {"y"};
            sessions_[net]->Run(Ort::RunOptions{nullptr}, inNames, &in, 1, outNames, &o, 1);
            return true;
        } catch (const Ort::Exception& e) {
            if (error) *error = e.what();
        } catch (const std::exception& e) {
            if (error) *error = e.what();
        }
        return false;
    }

private:
    int threads_;
    bool loaded_ = false;
    std::array<std::unique_ptr<Ort::Session>, kNetCount> sessions_;
};

}  // namespace

std::unique_ptr<Separator> createSpleeterOnnx(int threads) {
    return std::make_unique<SpleeterOnnx>(threads);
}

}  // namespace stems
}  // namespace hype
