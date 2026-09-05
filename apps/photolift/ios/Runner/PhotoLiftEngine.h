// Objective-C face of the shared C++ upscaling core (native/photolift_core.cpp)
// so Swift (UpscaleBridge.swift) can drive it without touching C++ headers.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^PhotoLiftProgress)(int done, int total);

/// Error codes mirror photolift::ErrorCode in photolift_core.h.
FOUNDATION_EXPORT const int PhotoLiftErrOk;          // 0
FOUNDATION_EXPORT const int PhotoLiftErrCancelled;   // -100

@interface PhotoLiftEngine : NSObject

/// Loads a Real-ESRGAN ncnn model. `preferGpu` is accepted for contract
/// parity with Android but ignored: the bundled ncnn iOS build is CPU-only
/// (Vulkan on iOS would need MoltenVK — see PLAN.md).
- (BOOL)loadParam:(NSString *)paramPath bin:(NSString *)binPath preferGpu:(BOOL)preferGpu;

@property(nonatomic, readonly) BOOL loaded;
@property(nonatomic, readonly) BOOL gpuActive;

- (int)tileCountForWidth:(int)width height:(int)height tile:(int)tile;

/// Runs the network over an RGBA (RGBX) buffer into an RGBA buffer that is
/// exactly `scale` times larger. Returns a photolift error code; progress is
/// called on the calling thread after every tile.
- (int)processRGBA:(const uint8_t *)input
             width:(int)width
            height:(int)height
          inStride:(int)inStride
            output:(uint8_t *)output
         outStride:(int)outStride
             scale:(int)scale
              tile:(int)tile
           overlap:(int)overlap
          progress:(nullable PhotoLiftProgress)progress;

/// Thread-safe; the running process returns PhotoLiftErrCancelled.
- (void)cancel;

+ (NSString *)describeError:(int)code;

@end

NS_ASSUME_NONNULL_END
