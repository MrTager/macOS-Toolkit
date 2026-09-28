#import "TouchBarBridge.h"
#import <dlfcn.h>

// Uses the private Control Strip entry points documented by the open-source
// MacDuo project (MIT). Resolve them at runtime so unsupported macOS releases
// continue to launch Toolkit with its regular menu bar controls.
@interface NSTouchBarItem (ToolkitControlStrip)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (ToolkitSystemModal)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar systemTrayItemIdentifier:(NSString *)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)bar;
@end

typedef void (*PresenceFunction)(NSString *, BOOL);
typedef void (*CloseBoxFunction)(BOOL);
static CloseBoxFunction closeBoxFunction;

static PresenceFunction presenceFunction(void) {
    static PresenceFunction presence;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
        if (framework) {
            presence = (PresenceFunction)dlsym(framework, "DFRElementSetControlStripPresenceForIdentifier");
            closeBoxFunction = (CloseBoxFunction)dlsym(framework, "DFRSystemModalShowsCloseBoxWhenFrontMost");
        }
    });
    return presence;
}

BOOL toolkit_touchbar_supported(void) {
    return presenceFunction() &&
        [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)] &&
        [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)] &&
        [NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:systemTrayItemIdentifier:)] &&
        [NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)];
}

BOOL toolkit_touchbar_register(NSTouchBarItem *item) {
    if (!toolkit_touchbar_supported()) return NO;
    @try {
        if (closeBoxFunction) closeBoxFunction(YES);
        [NSTouchBarItem addSystemTrayItem:item];
        presenceFunction()(item.identifier, YES);
        return YES;
    } @catch (NSException *exception) {
        toolkit_touchbar_unregister(item);
        return NO;
    }
}

void toolkit_touchbar_unregister(NSTouchBarItem *item) {
    @try {
        if (presenceFunction()) presenceFunction()(item.identifier, NO);
        if ([NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)])
            [NSTouchBarItem removeSystemTrayItem:item];
    } @catch (NSException *exception) { }
}

BOOL toolkit_touchbar_present(NSTouchBar *bar, NSString *identifier) {
    if (!toolkit_touchbar_supported()) return NO;
    @try {
        [NSTouchBar presentSystemModalTouchBar:bar systemTrayItemIdentifier:identifier];
        return YES;
    } @catch (NSException *exception) { return NO; }
}

void toolkit_touchbar_dismiss(NSTouchBar *bar) {
    @try {
        if ([NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)])
            [NSTouchBar dismissSystemModalTouchBar:bar];
    } @catch (NSException *exception) { }
}
