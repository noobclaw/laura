// Objective-C++ wrapper around photolift::Engine (see PhotoLiftEngine.h).
#import "PhotoLiftEngine.h"

#include "photolift_core.h"

const int PhotoLiftErrOk = photolift::kOk;
const int PhotoLiftErrCancelled = photolift::kErrCancelled;

namespace {
void forwardProgress(void *user, int done, int total) {
    PhotoLiftProgress block = (__bridge PhotoLiftProgress)user;
    if (block) block(done, total);
}
}  // namespace

@implementation PhotoLiftEngine {
    photolift::Engine *_engine;
}

- (instancetype)init {
    if ((self = [super init])) {
        _engine = new photolift::Engine();
    }
    return self;
}

- (void)dealloc {
    delete _engine;
    _engine = nullptr;
}

- (BOOL)loadParam:(NSString *)paramPath bin:(NSString *)binPath preferGpu:(BOOL)preferGpu {
    const int rc = _engine->loadFromFiles(paramPath.fileSystemRepresentation,
                                          binPath.fileSystemRepresentation,
                                          preferGpu == YES, 4);
    if (rc != photolift::kOk) {
        NSLog(@"PhotoLift: model load failed: %s", photolift::Engine::errorString(rc));
        return NO;
    }
    return YES;
}

- (BOOL)loaded {
    return _engine->loaded();
}

- (BOOL)gpuActive {
    return _engine->gpuActive();
}

- (int)tileCountForWidth:(int)width height:(int)height tile:(int)tile {
    return photolift::tileCount(width, height, tile);
}

- (int)processRGBA:(const uint8_t *)input
             width:(int)width
            height:(int)height
          inStride:(int)inStride
            output:(uint8_t *)output
         outStride:(int)outStride
             scale:(int)scale
              tile:(int)tile
           overlap:(int)overlap
          progress:(PhotoLiftProgress)progress {
    _engine->cancelFlag.store(false);
    void *user = progress ? (__bridge void *)progress : nullptr;
    return _engine->process(input, width, height, 4, inStride,
                            output, 4, outStride,
                            scale, tile, overlap,
                            progress ? forwardProgress : nullptr, user);
}

- (void)cancel {
    _engine->cancelFlag.store(true);
}

+ (NSString *)describeError:(int)code {
    return [NSString stringWithUTF8String:photolift::Engine::errorString(code)];
}

@end
