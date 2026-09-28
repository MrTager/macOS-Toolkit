#import <AppKit/AppKit.h>

BOOL toolkit_touchbar_supported(void);
BOOL toolkit_touchbar_register(NSTouchBarItem *item);
void toolkit_touchbar_unregister(NSTouchBarItem *item);
BOOL toolkit_touchbar_present(NSTouchBar *bar, NSString *identifier);
void toolkit_touchbar_dismiss(NSTouchBar *bar);
