#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the reason if it raised an Objective-C exception, nil if it did not.
///
/// AVAudioEngine raises (rather than returning an error) when a node is connected in a format
/// the hardware does not have at that instant, which happens for a moment while the route is
/// changing. Swift cannot catch that, and uncaught it ends the app.
NSString *_Nullable TapesReasonRaised(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
